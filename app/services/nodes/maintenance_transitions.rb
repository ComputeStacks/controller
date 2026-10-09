module Nodes
  ##
  # Reacts when a node's EFFECTIVE maintenance (`Node#maintenance`: the controller's
  # request OR a hold the node placed itself) flips.
  #
  # Called by both writers of its inputs -- NodeServices::MaintenanceRequestService
  # (the request) and Nodes::MaintenanceProjection (the agent's holds) -- with the
  # value before and after their write. They can race on one transition (e.g. a
  # release the agent reports back while the service is still finishing), so each
  # transition is claimed once in Redis before it is acted on.
  #
  #   false -> true: an EventLog. Nothing is kicked; the node simply drops out of
  #                  Node.online and the gates keyed on it.
  #   true -> false: an EventLog, then the recovery kicks: HealthCheck (restarts
  #                  active containers, refreshes status, resumes billing), the
  #                  region's LB config, an immediate changelog poll, a replay
  #                  of the region's dropped agent writes, and the container power
  #                  actions parked while it was in maintenance. The customer notice
  #                  is cleared if the node is fully online.
  #                  NOT RecoverVolumeWorker -- the volumes never left the node.
  module MaintenanceTransitions
    DEDUPE_TTL = 5.minutes

    module_function

    # @param node [Node] reloaded after the write
    # @param was [Boolean] effective maintenance before the write
    # @param now [Boolean] effective maintenance after the write
    def handle(node, was:, now:)
      return if was.nil? || now.nil?
      was = was ? true : false
      now = now ? true : false
      return if was == now
      return unless claim!(node, now)

      if now
        log!(node, "node.maintenance.enable", "d220b46693f57ec0")
      else
        log!(node, "node.maintenance.disable", "9a69918983be2845")
        # Only clears when the node is not also disconnected (checked in the UPDATE).
        node.clear_customer_notice_if_online!
        kick_recovery!(node)
      end
    end

    # @return [Boolean] true when this caller owns the transition
    def claim!(node, now)
      key = "node_maintenance_transition:#{node.id}:#{now}:#{node.maintenance_seq}:#{node.maintenance_gen}"
      Sidekiq.redis { |c| c.call("SET", key, "1", "NX", "EX", DEDUPE_TTL.to_i) } == "OK"
    rescue => e
      # Without Redis, kicking twice (all idempotent) beats not kicking at all.
      ExceptionAlertService.new(e, "36af8dc18c4f4636").perform
      true
    end

    def kick_recovery!(node)
      NodeWorkers::HealthCheckWorker.perform_async node.global_id.to_s
      if node.region&.load_balancer
        LoadBalancerWorkers::DeployConfigWorker.perform_async node.region.load_balancer.global_id.to_s
      end
      AgentWorkers::ChangelogPollWorker.perform_async node.global_id.to_s if node.agent_token.present?
      # Re-push agent writes dropped while the node was out (agent_pending_syncs).
      AgentWorkers::PendingSyncWorker.perform_async node.region_id if node.region_id
      # Run the container power actions parked while the node was in maintenance.
      ContainerWorkers::DeferredPowerWorker.perform_async node.id
    end

    def log!(node, locale, code)
      held = node.maintenance_held_by
      reason = if held.empty?
        "No holds remain."
      else
        parts = []
        parts << "controller#{" (#{node.maintenance_reason})" if node.maintenance_reason.present?}" if held.include?("controller")
        if held.include?("node")
          local = node.maintenance_local_hold
          parts << "node#{" (#{local["reason"]})" if local["reason"].present?}"
        end
        "Held by #{parts.join(" and ")}."
      end
      event = EventLog.create!(
        locale: locale,
        locale_keys: {"node" => node.label},
        event_code: code,
        status: "completed",
        state_reason: reason
      )
      event.nodes << node
    end
  end
end
