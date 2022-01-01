module ProjectWorkers
  class TrashProjectWorker
    include Sidekiq::Worker
    sidekiq_options retry: false

    def perform(project_id, event_id)
      project = GlobalID::Locator.locate project_id
      event = GlobalID::Locator.locate event_id

      event.start!

      if ProjectServices::TrashProject.new(project, event).perform
        event.done!
      else
        event.fail! 'Fatal error destroying project'
      end

    rescue => e
      user = nil
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: '108e3566f4cc9f43'
        )
        event.fail! e.message
      end
      ExceptionAlertService.new(e, '108e3566f4cc9f43', user).perform
    end
  end
end
