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

    def online?
      !disconnected && !maintenance
    end

    def toggle_evacuation!
      under_evacuation? ? update(job_status: 'idle') : update(job_status: 'evacuating', job_performed: Time.now)
    end

    def toggle_checkup!
      performing_checkup? ? update(job_status: 'idle') : update(job_status: 'checkup', job_performed: Time.now)
    end

    def toggle_maintenance!
      update maintenance: maintenance ? false : true, maintenance_updated: Time.now, job_status: 'idle'
    end

    def under_evacuation?
      if job_status == 'evacuating' && (Time.now - job_performed) > 30.minutes
        update_attribute :job_status, 'idle'
        false
      else
        job_status == 'evacuating'
      end
    end

    def performing_checkup?
      if job_status == 'checkup' && (Time.now - job_performed) > 30.minutes
        update_attribute :job_status, 'idle'
        false
      else
        job_status == 'checkup'
      end
    end

    def offline!
      update(
        disconnected: true,
        disconnected_at: Time.now
      )
      NodeWorkers::EvacuateNodeWorker.perform_async to_global_id.to_s
    end

    def online!
      update(
        failed_health_checks: 0,
        disconnected: false,
        online_at: Time.now
      )
      toggle_evacuation! if under_evacuation?
      NodeWorkers::HealthCheckWorker.perform_async to_global_id.to_s
      NodeWorkers::RecoverVolumeWorker.perform_in 5.minutes, to_global_id.to_s
      # Ensure node has most recent lb config
      if region.load_balancer
        LoadBalancerWorkers::DeployConfigWorker.perform_async region.load_balancer.to_global_id.to_s
      end
    end

  end
end
