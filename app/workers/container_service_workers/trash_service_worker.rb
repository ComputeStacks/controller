module ContainerServiceWorkers
  class TrashServiceWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(service_id, event_id)
      service = GlobalID::Locator.locate service_id
      event = GlobalID::Locator.locate event_id

      project = service.deployment

      event.start!

      if ContainerServices::TrashService.new(service, event).perform
        # Trigger a re-sync of the SFTP containers
        # Event will be closed out by this job
        ProjectWorkers::SftpInitWorker.perform_async project.to_global_id.to_s, event_id
        ProjectServices::StoreMetadata.new(project).perform
      else
        event.fail! 'Error deleting service'
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
      ExceptionAlertService.new(e, '70cde3ba6c2c9a57', user).perform
    end

  end
end
