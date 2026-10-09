module AgentWorkers
  ##
  # Delivers the controller's maintenance hold to the node's agent (>= 3.4).
  #
  # Enqueued by NodeServices::MaintenanceRequestService after every request, even an
  # unchanged one. Everything it sends is read from the DB under the per-node
  # advisory lock (shared with MaintenanceDriftWorker), never from job args, so a
  # delayed or duplicated job always sends the current decision; the agent refuses a
  # gen older than the newest it has applied (409), so no ordering is needed.
  #
  #   requested     -> PUT    /v1/admin/maintenance {reason, gen}
  #   not requested -> DELETE /v1/admin/maintenance?gen=N
  #   override pending (maintenance_override_gen == gen) -> GET the agent's status
  #                    first (or use the body the drift pass just read), then:
  #                    - a node hold placed no later than the override ->
  #                      DELETE ?gen=N&all=1&local_since_max=<override time>, which the
  #                      agent refuses (412) if a newer node hold appeared since the GET
  #                    - no node hold, or one placed after the override -> retire the
  #                      override, and plain DELETE only if a controller hold remains
  #                    (Nodes::MaintenanceProjection.override_decision)
  #
  #   200 -> project the returned Status; clear a delivered override
  #   412 -> the override met a node hold placed after it: project, retire, and send
  #          whatever the current decision is now (a plain DELETE if a controller hold remains)
  #   409 -> the agent is ahead of us (only after a controller DB restore): jump our
  #          gen past it, re-arm a pending override, alert, and push once more
  #   404 -> agent < 3.4: Nodes::MaintenanceProjection.mark_unsupported!
  #   else (transport error, 5xx, other) -> raise; Sidekiq retries
  class PushMaintenanceWorker
    include Sidekiq::Worker

    sidekiq_options retry: 12, queue: "default"

    LOCK_RETRY_DELAY = 5.seconds
    MAX_REASON_BYTES = 512 # the agent's cap
    DEFAULT_REASON = "maintenance requested by the controller" # the agent requires a reason

    class DeliveryError < StandardError; end

    sidekiq_retries_exhausted do |job, ex|
      node = Node.find_by(id: job["args"]&.first)
      label = node&.label || "node #{job["args"]&.first}"
      SystemEvent.create!(
        message: "controller maintenance hold not delivered to #{label}",
        log_level: "warn",
        data: {"node_id" => node&.id, "error" => ex&.message},
        event_code: "2765061d93591b4f"
      )
    end

    # @param node_id [Integer]
    # @param conflict_retry [Boolean] true on the single re-push after a 409
    def perform(node_id, conflict_retry = false)
      node = Node.find_by(id: node_id)
      return if node.nil?

      acquired, _ = Nodes::MaintenanceProjection.with_lock(node) do
        deliver(node, conflict_retry: conflict_retry)
      end
      self.class.perform_in(LOCK_RETRY_DELAY, node_id, conflict_retry) unless acquired
    end

    # Send the current decision and handle the answer. The caller MUST hold the
    # per-node lock (MaintenanceDriftWorker calls this from inside it).
    # @param observed [Hash, nil] a Status body already read (and projected) under this
    #   lock; spares the GET a pending override otherwise needs
    # @return [Array(Integer, Hash|nil), nil] the agent's [status, body], or nil if skipped.
    #   When a retired override leaves nothing to send, the status read it was judged on.
    def deliver(node, conflict_retry: false, observed: nil)
      node.reload
      return nil unless node.agent_maintenance_supported? # no token, or a 404 within the hour

      client = Agent::Client.for_node(node)
      override = false
      if Nodes::MaintenanceProjection.override_pending?(node)
        current = observed || read_status(node, client)
        return current if current.is_a?(Array) # the GET answered 404
        case (decision = Nodes::MaintenanceProjection.override_decision(node, current))
        when :apply
          override = true
        when :retire, :retire_newer
          Nodes::MaintenanceProjection.retire_override!(node, decision, current)
          # Nothing left for the override; release a controller hold if one remains.
          return [200, current] unless current["controller"].is_a?(Hash)
        end
        # nil: a request landed during the GET and replaced the override; send it.
      end

      gen = node.maintenance_gen # read after any GET: the node was reloaded
      status, body =
        if node.maintenance_requested
          client.put_maintenance(reason: reason_for(node), gen: gen)
        else
          # Floor to whole seconds, as the agent's `since` is; a hold placed in the
          # override's own second counts as predating it.
          client.delete_maintenance(gen: gen, all: override,
            local_since_max: (node.maintenance_updated.to_i if override))
        end

      case status
      when 200
        Nodes::MaintenanceProjection.apply_snapshot(node, body, seq: body["seq"]) if body.is_a?(Hash)
        if override
          Node.where(id: node.id, maintenance_override_gen: gen).update_all(maintenance_override_gen: nil)
        end
      when 412
        return [status, body] unless override && body.is_a?(Hash)
        Nodes::MaintenanceProjection.apply_snapshot(node, body, seq: body["seq"])
        node.reload
        # Retirement is guarded on override_gen, so a newer override that landed
        # meanwhile survives and is judged afresh by the re-delivery.
        Nodes::MaintenanceProjection.retire_override!(node, :retire_newer, body)
        return deliver(node, conflict_retry: conflict_retry, observed: body)
      when 409
        conflict!(node, gen, body, conflict_retry)
      when 404
        Nodes::MaintenanceProjection.mark_unsupported!(node)
      else
        raise DeliveryError, "agent maintenance #{node.maintenance_requested ? "PUT" : "DELETE"} on #{node.label} returned HTTP #{status}"
      end
      [status, body]
    end

    private

    # GET the agent's status before a pending override is acted on, and project it.
    # @return [Hash, Array(Integer, nil)] the Status body, or [404, nil] after marking
    #   the agent unsupported (which also drops the override)
    def read_status(node, client)
      status, body = client.get_maintenance
      if status == 404
        Nodes::MaintenanceProjection.mark_unsupported!(node)
        return [404, body]
      end
      unless status == 200 && body.is_a?(Hash)
        raise DeliveryError, "agent maintenance GET on #{node.label} returned HTTP #{status}"
      end
      Nodes::MaintenanceProjection.apply_snapshot(node, body, seq: body["seq"])
      node.reload
      body
    end

    def reason_for(node)
      (node.maintenance_reason.presence || DEFAULT_REASON).truncate_bytes(MAX_REASON_BYTES, omission: "")
    end

    # The agent has applied a newer gen than ours: our DB was restored behind it.
    # Jump past it so the current decision wins, keeping an override pending.
    def conflict!(node, sent_gen, body, conflict_retry)
      agent_gen = body.is_a?(Hash) ? Integer(body["controller_gen"], exception: false) : nil
      if agent_gen.nil?
        raise DeliveryError, "agent maintenance on #{node.label} returned 409 without a controller_gen"
      end

      # Every right-hand side reads the OLD row, so the CASE sees the pre-bump gen.
      # Guarded on the gen we sent: a request that bumped it meanwhile enqueued its
      # own push, which re-checks against the agent.
      new_gen = agent_gen + 1
      Node.where(id: node.id, maintenance_gen: sent_gen).where("maintenance_gen < ?", new_gen).update_all([<<~SQL, new_gen, new_gen])
        maintenance_gen = ?,
        maintenance_override_gen = CASE WHEN maintenance_override_gen = maintenance_gen THEN ? ELSE maintenance_override_gen END
      SQL
      SystemEvent.create!(
        message: "agent maintenance generation on #{node.label} [node #{node.id}] was ahead of the controller (#{agent_gen} > #{sent_gen}); re-sending as #{new_gen}",
        log_level: "warn",
        data: {"node_id" => node.id, "sent_gen" => sent_gen, "agent_gen" => agent_gen},
        event_code: "0b82958209e755c0"
      )
      self.class.perform_async(node.id, true) unless conflict_retry
    end
  end
end
