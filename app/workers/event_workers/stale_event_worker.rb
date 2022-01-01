module EventWorkers
  class StaleEventWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    def perform

      EventLog.where("status = 'running' AND updated_at < ?", 1.hour.ago).each do |event|
        event.event_details.create!(
          data: 'Timeout reached',
          event_code: 'c454cd8313103e66'
        )
        event.update(
          event_code: 'c454cd8313103e66',
          status: 'failed',
          state_reason: 'Timeout reached'
        )
      end

    rescue => e
      ExceptionAlertService.new(e, '79f66f02f9d3b511').perform
    end

  end
end
