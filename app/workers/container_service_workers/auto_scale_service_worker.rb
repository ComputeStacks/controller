module ContainerServiceWorkers
  class AutoScaleServiceWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(service_id, resource_kind)
      # @type [Deployment::ContainerService]
      service = GlobalID::Locator.locate service_id

      ContainerServices::AutoScaleService.new(service, resource_kind).perform

    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      user = nil
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: 'ea740f878da8bd88'
        )
        event.fail! e.message
        user = event.audit&.user
      end
      ExceptionAlertService.new(e, 'ea740f878da8bd88', user).perform
    end

  end
end
