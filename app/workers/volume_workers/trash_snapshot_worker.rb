module VolumeWorkers
  class TrashSnapshotWorker
    include Sidekiq::Worker

    sidekiq_options retry: 2, queue: 'low'

    def perform(vol_id, snapshot)

      vol = Volume.find_by id: vol_id
      return false unless vol

      vol.delete_backup!(snapshot)

    rescue => e
      ExceptionAlertService.new(e, '8039c87868e7369f').perform
    end

  end
end
