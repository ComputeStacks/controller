module RegionWorkers
  class VolumeUsageWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1, queue: 'low'

    def perform(region_id = nil)
      if region_id.nil?
        Region.all.each do |region|
          RegionWorkers::VolumeUsageWorker.perform_async region.to_global_id.to_s
        end
        return
      end
      region = GlobalID::Locator.locate region_id
      return if region.nil?
      region.volume_usage.each_pair do |id, size|
        vol = Volume.find_by(name: id)
        next if vol.nil?
        size_in_gb = size / KILOBYTE_TO_GB
        # Use update_column to avoid validation issues.
        # Regardless of state, we still need to record the size.
        vol.update_columns(
          usage: size_in_gb.round(4),
          usage_checked: Time.now
        )
      end

      ##
      # For non-local volumes, we also need to calculate usage for
      # locally-created, imported volumes.
      unless region.volume_backend == 'local'
        region.volumes.where(volume_backend: 'local').each do |vol|
          size = vol.volume_client.usage
          next if size.nil?
          size_in_gb = size / KILOBYTE_TO_GB
          vol.update_columns(
            usage: size_in_gb.round(4),
            usage_checked: Time.now
          )
        end
      end

    end

  end
end
