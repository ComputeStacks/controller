module ContainerWorkers
  class RecoverContainerWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [String] container_id GlobalID
    # @param [String] alert_id Global ID (optional)
    def perform(container_id, alert_id = nil)
      if alert_id
        alert = GlobalID::Locator.locate alert_id
        return unless alert.active?
      end
      container = GlobalID::Locator.locate container_id

      return unless container.node.online? # Ignore containers that are on disconnected nodes

      audit = Audit.create_from_object!(container, 'updated', '127.0.0.1')

      # TODO: Check if network interface is missing.
      #       see: `Containers::ContainerNetworking.has_network_interface?`
      #       Currently being handled by the node health check job.

      if container.docker_client
        PowerCycleContainerService.new(container, 'start', audit).perform
      else
        PowerCycleContainerService.new(container, 'rebuild', audit).perform
      end
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      ExceptionAlertService.new(e, 'fef9a051642bb924').perform
    end

  end
end

