module ContainerServiceWorkers
  class ResizeServiceWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(service_id, event_id, package_id)
      service = GlobalID::Locator.locate service_id
      event = GlobalID::Locator.locate event_id
      package = GlobalID::Locator.locate package_id

      event.start!
      success = true
      service.containers.each do |container|
        unless ProvisionServices::ContainerResizeProvisioner.new(container, event, package).perform
          success = false
        end
      end
      ProjectServices::StoreMetadata.new(service.deployment).perform
      success ? event.done! : event.fail!('Error resizing containers')
    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      user = nil
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: 'f25e7dbf2b735858'
        )
        event.fail! e.message
        user = event.audit&.user
      end
      ExceptionAlertService.new(e, 'f25e7dbf2b735858', user).perform
    end

  end
end
