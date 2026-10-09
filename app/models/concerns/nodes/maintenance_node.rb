##
# =Node Maintenance
#
# * Manage maintenance mode
# * Recovery & Failover
# * Prune docker images
#
module Nodes
  module MaintenanceNode
    extend ActiveSupport::Concern

    # `maintenance` is a STORED GENERATED column: the controller's request OR a
    # hold the node placed itself. It is read-only -- Rails drops writes to it
    # silently. Change the request through NodeServices::MaintenanceRequestService,
    # and `reload` to read the derived value after any write.
    def online?
      !disconnected && !maintenance
    end

    # The node's own hold (`cs-agent maintenance on`), or nil.
    # @return [Hash, nil]
    def maintenance_local_hold
      hold = (maintenance_holds || {})["local"]
      hold.is_a?(Hash) ? hold : nil
    end

    # The controller hold as the agent last reported it, or nil.
    # @return [Hash, nil]
    def maintenance_controller_hold
      hold = (maintenance_holds || {})["controller"]
      hold.is_a?(Hash) ? hold : nil
    end

    # Who is holding the node in maintenance. "controller" means requested here,
    # whether or not the agent has confirmed it yet.
    # @return [Array<String>]
    def maintenance_held_by
      held = []
      held << "controller" if maintenance_requested
      held << "node" if maintenance_local_hold
      held
    end

    # When the node entered maintenance: the agent's paused_since, else (only
    # while requested) when the request was made. Never a stale timestamp.
    # @return [Time, nil]
    def maintenance_since
      paused = (maintenance_holds || {})["paused_since"]
      if paused.present?
        # The agent sends unix seconds; accept ISO strings too.
        parsed = begin
          if paused.is_a?(Numeric) || paused.to_s.match?(/\A\d+\z/)
            Time.at(paused.to_i).utc
          else
            Time.zone.parse(paused.to_s)
          end
        rescue ArgumentError
          nil
        end
        return parsed if parsed
      end
      maintenance_requested ? maintenance_updated : nil
    end

    # The agent speaks the maintenance API (>= 3.4), as far as we know. A 404
    # marks it unsupported for an hour before it is tried again.
    def agent_maintenance_supported?
      agent_token.present? && (agent_maintenance_unsupported_at.nil? || agent_maintenance_unsupported_at < 1.hour.ago)
    end

    def toggle_evacuation!
      under_evacuation? ? update(job_status: "idle") : update(job_status: "evacuating", job_performed: Time.now)
    end

    def toggle_checkup!
      performing_checkup? ? update(job_status: "idle") : update(job_status: "checkup", job_performed: Time.now)
    end

    def under_evacuation?
      if job_status == "evacuating" && (Time.now - job_performed) > 30.minutes
        update_attribute :job_status, "idle"
        false
      else
        job_status == "evacuating"
      end
    end

    def performing_checkup?
      if job_status == "checkup" && (Time.now - job_performed) > 30.minutes
        update_attribute :job_status, "idle"
        false
      else
        job_status == "checkup"
      end
    end

    def offline!
      update(
        disconnected: true,
        disconnected_at: Time.now
      )
      NodeWorkers::EvacuateNodeWorker.perform_async global_id
    end

    # Reconnected: the state update plus the recovery kicks.
    def online!
      mark_online!
      kick_recovery!
    end

    # The state half of #online!: the node answers again. No kicks, so a node that
    # reconnects while in maintenance stays hands-off until the maintenance ends
    # (Nodes::MaintenanceTransitions kicks then).
    def mark_online!
      update(
        failed_health_checks: 0,
        disconnected: false,
        online_at: Time.now,
        maintenance_reconnect_attempts: 0
      )
      toggle_evacuation! if under_evacuation?
      clear_customer_notice_if_online!
      # Replay agent writes dropped while the node was unreachable.
      AgentWorkers::PendingSyncWorker.perform_async region_id if region_id
    end

    # Back to fully online: drop the customer notice so a stale message cannot reappear
    # at the next incident. One conditional UPDATE, re-checked against the row, so it never
    # clears a notice set for a node that is (again) disconnected or in maintenance.
    # Not audited (a system action).
    # @return [Boolean] true when a notice was cleared
    def clear_customer_notice_if_online!
      cleared = Node.where(id: id, disconnected: false, maintenance: false)
        .where.not(customer_notice: nil)
        .update_all(customer_notice: nil)
      return false if cleared.zero?
      self.customer_notice = nil
      clear_attribute_change(:customer_notice)
      Rails.logger.info "Node #{id}: back online, customer notice cleared"
      true
    end

    # The recovery half of #online!: restart containers, recover volumes, refresh
    # the region's load balancer config.
    def kick_recovery!
      NodeWorkers::HealthCheckWorker.perform_async global_id
      NodeWorkers::RecoverVolumeWorker.perform_in 5.minutes, global_id
      ContainerWorkers::DeferredPowerWorker.perform_async id
      # Ensure node has most recent lb config
      if region.load_balancer
        LoadBalancerWorkers::DeployConfigWorker.perform_async region.load_balancer.global_id
      end
    end
  end
end
