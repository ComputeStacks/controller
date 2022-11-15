module VolumeWorkers
  class TrashVolumeWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: 'low'

    def perform(volume_id = nil)
      if volume_id.nil?
        Volume.trashable.each do |i|
          # If any nodes are offline, then wait to trash this one later.
          next if i.nodes.offline.exists?
          VolumeWorkers::TrashVolumeWorker.perform_async i.to_global_id.to_s
        end
        return
      end
      volume = GlobalID::Locator.locate volume_id
      return false if volume.trash_after.nil? || !volume.to_trash

      # After 3 failed attempts, stop.
      halt_attempt = volume.event_logs.where( Arel.sql(%Q(created_at > '#{volume.trash_after.iso8601}' AND event_code = '26045910b65d1d4f' AND status = 'failed')) ).count > 3

      audit = volume.trashed_by
      audit = Audit.create_from_object!(volume, 'deleted', '127.0.0.1') if audit.nil?
      audit.update_attribute :raw_data, { name: volume.name }

      event = EventLog.create!(
        locale: 'volume.delete',
        locale_keys: { 'volume' => volume.name },
        event_code: '26045910b65d1d4f',
        status: 'running',
        audit: audit
      )
      event.volumes << volume

      if halt_attempt
        if defined?(event) && event
          event.event_details.create!(
            data: "Too many failed attempts to remove this volume. Please check previous events for errors and try again.",
            event_code: "56a8af7da2e3b652"
          )
          event.cancel!("Too many failed attempts")
        end
        volume.update to_trash: false, trash_after: nil, trashed_by: nil
        return false
      end

      VolumeServices::TrashVolumeService.new(volume, event).perform
    rescue Docker::Error::ConflictError
      # volume is in use
      if defined?(event) && event
        event.event_details.create!(
          data: "Volume is currently in use. Please stop and remove any associated container before attempting to delete it",
          event_code: 'de7123e54ba18968'
        )
        event.fail! 'Volume in use'
        if defined?(volume)
          if volume && volume.event_logs.where(event_code: '26045910b65d1d4f', status: 'failed').count > 2
            volume.update to_trash: false
          end
        end
      elsif defined?(volume) && volume
        volume.update_column(:trash_after, 1.day.from_now)
      end
    rescue => e
      ExceptionAlertService.new(e, 'e4dcc06b2c60061f').perform
      if defined?(event) && event
        event.event_details.create!(
          data: e.message,
          event_code: 'e4dcc06b2c60061f'
        )
        event.fail! 'Fatal Error'
      end
    end

  end
end
