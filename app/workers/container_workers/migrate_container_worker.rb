module ContainerWorkers
  class MigrateContainerWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'dep'

    def perform(container_id, event_id)
      event = GlobalID::Locator.locate event_id
      begin
        container = GlobalID::Locator.locate container_id
      rescue ActiveRecord::RecordNotFound
        event.fail! "Unknown container"
        return
      end


      migrator = ContainerMigratorService.new(container, event)
      migrator.perform ? event.done! : event.fail!('Fatal Error')
    rescue ActiveRecord::RecordNotFound
      return
    rescue => e
      ExceptionAlertService.new(e, '2534269aa9d128cf').perform
    end

  end
end
