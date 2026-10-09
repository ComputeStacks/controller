module NodeServices
  ##
  # The ONLY writer of the controller's maintenance hold (`maintenance_requested`).
  #
  # `Node#maintenance` is a generated column (requested OR a hold the node placed
  # itself), so it cannot be written directly. Every request -- admin UI, admin
  # API, runner -- goes through here so the generation is bumped, the change is
  # audited with the actor and IP, and the agent is told.
  #
  #   NodeServices::MaintenanceRequestService.new(node, on: true, reason: "kernel", actor: user, remote_ip: ip).perform
  #
  # `override_all: true` forces `on: false` and, on the next push, clears BOTH
  # holds on the agent -- including a forgotten `cs-agent maintenance on`. It
  # always bumps the generation, even when requested is already false.
  #
  # The push is enqueued even when nothing changed, so retries are safe and a
  # lost push is redelivered.
  class MaintenanceRequestService
    attr_reader :node, :on, :reason, :actor, :remote_ip, :override_all, :event

    def initialize(node, on:, reason: nil, actor: nil, remote_ip: nil, override_all: false)
      @node = node
      @override_all = override_all ? true : false
      @on = @override_all ? false : ActiveModel::Type::Boolean.new.cast(on) == true
      @reason = reason.to_s.strip.presence
      @actor = actor
      @remote_ip = remote_ip.presence || "127.0.0.1"
      @changed = false
      @event = nil
    end

    # @return [Boolean]
    def perform
      was = nil
      Node.transaction do
        locked = Node.lock.find(node.id)
        was = locked.maintenance
        if override_all
          # In an UPDATE every right-hand side reads the OLD row, so both
          # columns receive the same new generation.
          bump!(<<~SQL, false, reason)
            UPDATE nodes SET maintenance_requested = $1, maintenance_reason = $2,
              maintenance_gen = maintenance_gen + 1,
              maintenance_override_gen = maintenance_gen + 1,
              maintenance_updated = now()
            WHERE id = $3 RETURNING maintenance_gen
          SQL
        elsif on != locked.maintenance_requested
          bump!(<<~SQL, on, reason)
            UPDATE nodes SET maintenance_requested = $1, maintenance_reason = $2,
              maintenance_gen = maintenance_gen + 1,
              maintenance_override_gen = NULL,
              maintenance_updated = now()
            WHERE id = $3 RETURNING maintenance_gen
          SQL
        end
        record! if changed?
      end

      AgentWorkers::PushMaintenanceWorker.perform_async(node.id)
      node.reload
      Nodes::MaintenanceTransitions.handle(node, was: was, now: node.maintenance)
      true
    end

    # Whether this call changed the request (an override always does).
    def changed?
      @changed
    end

    # The generation written by this call, or nil when nothing changed.
    attr_reader :gen

    private

    def bump!(sql, value, reason)
      binds = [
        ActiveRecord::Relation::QueryAttribute.new("maintenance_requested", value, ActiveRecord::Type::Boolean.new),
        ActiveRecord::Relation::QueryAttribute.new("maintenance_reason", reason, ActiveRecord::Type::String.new),
        ActiveRecord::Relation::QueryAttribute.new("id", node.id, ActiveRecord::Type::Integer.new)
      ]
      result = Node.connection.exec_query(sql, "MaintenanceRequest", binds)
      @gen = result.rows.dig(0, 0).to_i
      @changed = true
    end

    def record!
      audit = Audit.create_from_object!(node, "updated", remote_ip, actor)
      locale = if override_all
        "node.maintenance.override"
      else
        on ? "node.maintenance.requested" : "node.maintenance.released"
      end
      @event = EventLog.create!(
        locale: locale,
        locale_keys: {"node" => node.label},
        event_code: event_code,
        audit: audit,
        status: "completed",
        state_reason: reason
      )
      @event.nodes << node
      return unless override_all

      SystemEvent.create!(
        message: "Maintenance override on #{node.label}: releasing ALL holds, including the node's own",
        log_level: "warn",
        data: {
          "node_id" => node.id,
          "gen" => gen,
          "reason" => reason,
          "actor" => actor&.respond_to?(:email) ? actor.email : nil
        },
        event_code: "a70680386c4f8542",
        audit: audit
      )
    end

    def event_code
      if override_all
        "3a10a77348148a8c"
      else
        on ? "18ba5ad19c9f0c85" : "f782cef53b82a709"
      end
    end
  end
end
