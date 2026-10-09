module Nodes
  ##
  # Projects the agent's maintenance state onto the node: the ONLY writer of
  # `maintenance_holds`, `maintenance_seq` and `agent_instance_id`.
  #
  # Two sources feed it, both full snapshots: a `node_maintenance` changelog entry
  # (seq = the entry's own `seq`; the payload carries none) and the Status body the
  # agent returns from GET/PUT/DELETE /v1/admin/maintenance (seq = its `seq`, the
  # seq of the newest node_maintenance entry). A snapshot is applied only when its
  # seq is newer than the stored one, so a late or replayed snapshot can't regress.
  #
  # Also holds the per-node advisory lock shared by PushMaintenanceWorker and
  # MaintenanceDriftWorker, so a push and a drift reconcile never interleave.
  module MaintenanceProjection
    # Shared with AgentWorkers::PushMaintenanceWorker and MaintenanceDriftWorker.
    ADVISORY_LOCK_CLASS = 0x63730002

    # Status-body fields that describe work in flight or identity, not holds.
    # `running`/`pending`/`quiesce` go to `maintenance_status` (drift's column).
    NON_HOLD_KEYS = %w[instance_id seq running pending quiesce].freeze

    module_function

    # @param node [Node]
    # @param payload [Hash] the changelog payload or the Status body
    # @param seq [Integer] the entry's seq, or the Status body's seq
    # @return [Boolean] whether the snapshot was applied (false = stale or malformed)
    def apply_snapshot(node, payload, seq:)
      return false unless payload.is_a?(Hash)
      seq = Integer(seq, exception: false)
      return false if seq.nil?

      was = now = nil
      applied = false
      replaced = nil
      locked = nil
      Node.transaction do
        locked = Node.lock.find(node.id)
        was = locked.maintenance
        instance = payload["instance_id"].presence&.to_s
        if instance && locked.agent_instance_id.nil?
          locked.update_columns(agent_instance_id: instance) # first contact: adopt silently
        elsif instance && locked.agent_instance_id != instance
          # control.db was replaced: its seq restarted, so the old guard means nothing.
          replaced = [locked.agent_instance_id, instance]
          locked.update_columns(agent_instance_id: instance, maintenance_seq: 0)
        end

        scope = Node.where(id: locked.id)
        # A replaced control.db may report seq 0 (no entry yet) while our stored holds
        # still describe the old one; take its snapshot regardless of seq.
        scope = scope.where("maintenance_seq < ?", seq) unless replaced
        applied = scope.update_all(maintenance_holds: payload.except(*NON_HOLD_KEYS), maintenance_seq: seq) == 1
        locked.reload
        now = locked.maintenance
      end

      report_instance_change(locked, *replaced) if replaced
      node.reload unless node.equal?(locked)
      Nodes::MaintenanceTransitions.handle(locked, was: was, now: now)
      applied
    end

    # The agent answered 404 to the maintenance API: it predates 3.4. Forget what it
    # last reported, so effective maintenance falls back to the controller's request
    # alone (an agent rolled back below 3.4 would otherwise pin the node in
    # maintenance with no way out from here). Retried after an hour.
    # @param node [Node]
    def mark_unsupported!(node)
      was = now = nil
      first = false
      locked = nil
      Node.transaction do
        locked = Node.lock.find(node.id)
        was = locked.maintenance
        # Only the first mark (or one that drops reported holds) is worth an EventLog;
        # an old agent is re-probed hourly and would otherwise log every hour.
        first = locked.agent_maintenance_unsupported_at.nil? || locked.maintenance_holds.present?
        locked.update_columns(
          agent_maintenance_unsupported_at: Time.current,
          maintenance_holds: {},
          maintenance_seq: 0,
          agent_instance_id: nil,
          maintenance_override_gen: nil # an agent < 3.4 holds nothing to override
        )
        locked.reload
        now = locked.maintenance
      end

      log_unsupported(locked) if first
      node.reload unless node.equal?(locked)
      Nodes::MaintenanceTransitions.handle(locked, was: was, now: now)
      true
    end

    # What a pending override (MaintenanceRequestService `override_all`) should do,
    # judged from the agent's live Status body. An override may only release a node
    # hold that already existed when it was requested: its time is
    # `maintenance_updated`, which the service sets in the same UPDATE as
    # `maintenance_override_gen`, and any later request NULLs override_gen.
    #
    # @param node [Node] freshly reloaded
    # @param body [Hash] the agent's Status body
    # @return [Symbol, nil]
    #   nil            -- no override pending (override_gen != gen, or requested)
    #   :apply         -- send DELETE all=1: the local hold predates the override
    #   :retire        -- nothing left to do: the agent holds no local hold
    #   :retire_newer  -- the local hold was placed after the override (or carries no
    #                     readable `since`): never released by it
    # The boundary compares the DB's maintenance_updated with the agent's own clock,
    # so it is only as sharp as NTP skew between the two (a second or so).
    def override_decision(node, body)
      return nil unless override_pending?(node)

      local = body.is_a?(Hash) ? body["local"] : nil
      return :retire unless local.is_a?(Hash)

      since = hold_since(local["since"])
      requested_at = node.maintenance_updated&.to_i
      return :apply if since && requested_at && since <= requested_at
      :retire_newer
    end

    # An override is pending while it is the current request (override_gen == gen).
    # @param node [Node]
    def override_pending?(node)
      !node.maintenance_requested && !node.maintenance_override_gen.nil? &&
        node.maintenance_override_gen == node.maintenance_gen
    end

    # Retire a pending override that has nothing left to do, guarded on the
    # override_gen read, so a newer override requested meanwhile survives.
    # @param node [Node]
    # @param decision [Symbol] :retire or :retire_newer (from #override_decision)
    # @param body [Hash] the agent's Status body the decision was made on
    # @return [Boolean] whether this call retired it
    def retire_override!(node, decision, body)
      gen = node.maintenance_override_gen
      return false if gen.nil?
      retired = Node.where(id: node.id, maintenance_override_gen: gen).update_all(maintenance_override_gen: nil) == 1
      if retired && decision == :retire_newer
        local = body.is_a?(Hash) && body["local"].is_a?(Hash) ? body["local"] : {}
        SystemEvent.create!(
          message: "Maintenance override on #{node.label} [node #{node.id}] not applied: node hold placed after it",
          log_level: "info",
          data: {
            "node_id" => node.id,
            "override_gen" => gen,
            "override_at" => node.maintenance_updated&.iso8601,
            "local" => local.slice("since", "reason", "by")
          },
          event_code: "c4b19e2f7a0d6385"
        )
      end
      node.maintenance_override_gen = nil if retired
      retired
    end

    # The agent reports `since` as unix seconds; accept an Integer/Float or a digit string.
    # @return [Integer, nil]
    def hold_since(value)
      case value
      when Numeric then value.to_i
      when /\A\d+\z/ then value.to_i
      end
    end

    # Run the block holding this node's maintenance advisory lock (session level,
    # so it spans the HTTP call). Never blocks: on a miss the block doesn't run.
    # @return [Array(Boolean, Object)] [acquired, block result]
    def with_lock(node)
      conn = ActiveRecord::Base.connection
      id = node.id.to_i
      return [false, nil] unless conn.select_value("SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_CLASS}, #{id})")
      begin
        [true, yield]
      ensure
        conn.execute("SELECT pg_advisory_unlock(#{ADVISORY_LOCK_CLASS}, #{id})")
      end
    end

    def report_instance_change(node, old_id, new_id)
      SystemEvent.create!(
        message: "agent control.db replaced on #{node.label} [node #{node.id}]: maintenance state re-synced from the new instance",
        log_level: "warn",
        data: {"node_id" => node.id, "old_instance_id" => old_id, "new_instance_id" => new_id},
        event_code: "356126ba18ab3539"
      )
    end

    def log_unsupported(node)
      event = EventLog.create!(
        locale: "node.maintenance.unsupported",
        locale_keys: {"node" => node.label},
        event_code: "a18e102e989c0ab6",
        status: "completed",
        state_reason: "The agent on this node predates the maintenance API (cs-agent < 3.4.0); maintenance is not enforced on the node."
      )
      event.nodes << node
    end
  end
end
