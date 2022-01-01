module VolumeWorkers
  class SyncLocalVolumeWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'low'

    def perform
      audit = Audit.create!(
        event: 'updated',
        rel_id: nil,
        rel_model: 'Volume'
      )
      event = EventLog.create!(
        locale: 'system.sync_volumes',
        event_code: 'f99c17d69be552bc',
        audit: audit,
        status: 'running'
      )
      VolumeServices::SyncVolumeService.new(event).perform
      event.done! if event.running?
    rescue => e
      ExceptionAlertService.new(e, '70d876085cec6b64').perform
    end

  end
end
