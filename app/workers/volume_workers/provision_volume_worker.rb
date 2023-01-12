module VolumeWorkers
  class ProvisionVolumeWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'low'

    def perform(volume_id)
      volume = GlobalID::Locator.locate volume_id
      VolumeServices::ProvisionVolumeService.new(volume, nil).perform
    rescue ActiveRecord::RecordNotFound
      return
    rescue => e
      ExceptionAlertService.new(e, '87352cf62460c20e').perform
    end

  end
end
