module ContainerServiceWorkers
  class ScaleServiceWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(service_id, event_id)
      # @type [Deployment::ContainerService]
      service = GlobalID::Locator.locate service_id

      # @type [EventLog]
      event = GlobalID::Locator.locate event_id

      event.start!
      qty = event.locale_keys['to']
      unless ProvisionServices::ScaleServiceProvisioner.new(service, event, qty).perform
        unless event.failed?
          event.fail! 'Fatal Error'
        end
      end

    rescue ActiveRecord::RecordNotFound
      return # Silently fail
    rescue => e
      user = nil
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: '70cde3ba6c2c9a57'
        )
        event.fail! e.message
        user = event.audit&.user
      end
      ExceptionAlertService.new(e, '0f78f7b3f13c57ae', user).perform
    end

  end
end
