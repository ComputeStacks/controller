module EventWorkers
  class PruneEventWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    def perform
      usage_events
      zombie_events
      general_logs
    end

    private

    def general_logs
      EventLog.where("created_at < ?", 12.months.ago).delete_all
      Audit.where("created_at < ?", 12.months.ago).delete_all
      SystemEvent.where("created_at < ?", 12.months.ago).delete_all
    rescue => e
      ExceptionAlertService.new(e, '6b87e296c4f50ff0').perform
    end

    ##
    # Cleanup events storing usage items
    def usage_events
      EventLog.where("event_code = 'af5dbfa43bebd5f5' AND status = 'completed' AND created_at < ?", 3.months.ago).delete_all
      EventLog.where("event_code = 'af5dbfa43bebd5f5' AND created_at < ?", 6.months.ago).delete_all
    rescue => e
      ExceptionAlertService.new(e, '026c5e0acee33b22').perform
    end

    ##
    # Events with no associated object
    def zombie_events
      EventLog.joins(
        "
        LEFT JOIN deployments_event_logs on event_logs.id = deployments_event_logs.event_log_id
        LEFT JOIN event_logs_load_balancers on event_logs.id = event_logs_load_balancers.event_log_id
        LEFT JOIN event_logs_nodes on event_logs.id = event_logs_nodes.event_log_id
        LEFT JOIN event_logs_users on event_logs.id = event_logs_users.event_log_id
        LEFT JOIN event_logs_volumes on event_logs.id = event_logs_volumes.event_log_id
        LEFT JOIN deployment_sftps_event_logs on event_logs.id = deployment_sftps_event_logs.event_log_id
        LEFT JOIN container_registries_event_logs on event_logs.id = container_registries_event_logs.event_log_id
        LEFT JOIN deployment_container_services_event_logs on event_logs.id = deployment_container_services_event_logs.event_log_id
        "
      ).where(
        "deployments_event_logs.deployment_id IS NULL
        AND event_logs_load_balancers.load_balancer_id IS NULL
        AND event_logs_nodes.node_id IS NULL
        AND event_logs_users.user_id IS NULL
        AND event_logs_volumes.volume_id IS NULL
        AND deployment_sftps_event_logs.deployment_sftp_id IS NULL
        AND container_registries_event_logs.container_registry_id IS NULL
        AND deployment_container_services_event_logs.deployment_container_service_id IS NULL
        AND event_logs.created_at < ?
        ", 12.hours.ago
      ).delete_all
    rescue => e
      ExceptionAlertService.new(e, '8936c4fd322428d6').perform
    end

  end
end
