module VolumeServices
  ##
  # Provision Volume
  #
  # @!attribute volume
  #   @return [Volume]
  # @!attribute event
  #   @return [EventLog]
  class ProvisionVolumeService

    attr_accessor :volume,
                  :source_volume,
                  :source_snapshot, # In Base64
                  :event

    # @param [Volume] volume
    # @param [EventLog] event
    def initialize(volume, event)
      self.volume = volume
      self.event = event
      self.source_volume = nil
      self.source_snapshot = nil
    end

    # @return [Boolean]
    def perform
      event.event_details.create!(
        data: "[DEBUG] ProvisionVolumeService\n\nVolume: #{volume.id} | SourceVolume: #{source_volume&.id} | Snapshot: #{source_snapshot}",
        event_code: "7ab0bb2642a70951"
      ) unless Rails.env.production?
      volume.current_audit = event.audit
      source_volume.current_audit = event.audit if source_volume
      client = volume.volume_client
      if client.create!
        volume.update_consul!
      else
        if event
          event.event_details.create!(
            data: client.errors.empty? ? "Fatal error" : client.errors.join(' '),
            event_code: '3ace7a0db8fcc88f'
          )
        end
        return false
      end
      return false unless provision_from_volume!
      true
    rescue Excon::Error::Socket, Errno::ECONNREFUSED, IO::EINPROGRESSWaitWritable => connection_error
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume.inspect,
          error: connection_error.message
        },
        event_code: '04bed58fa43fab49'
      )
      event.event_details.create!(data: connection_error.message, event_code: "04bed58fa43fab49") if event
      false
    rescue Docker::Error::ServerError => server_error
      ExceptionAlertService.new(e, '7644f82e2a97cd0e').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume.inspect,
          error: server_error.message
        },
        event_code: '7644f82e2a97cd0e'
      )
      event.event_details.create!(data: server_error.message, event_code: "7644f82e2a97cd0e") if event
      false
    rescue Timeout::Error
      if defined?(clone_name)
        clone_event.update data: "[#{Time.now.strftime("%Y%m%d%H%M")}] Timeout reached while cloning source volume. \n#{clone_event.data}"
      end
      false
    rescue => e
      ExceptionAlertService.new(e, 'cec8b7094470e525').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume&.inspect,
          error: e.message
        },
        event_code: 'cec8b7094470e525'
      )
      event.event_details.create!(data: e.message, event_code: "cec8b7094470e525") if event
      false
    end

    def provision_from_volume!
      return true unless source_volume
      unless volume.region == source_volume.region
        event.event_details.create!(
          data: "Error! Requested source volume is not in this region.",
          event_code: "9a69eb920764c1da"
        )
        return false
      end

      clone_event = if source_snapshot
                      event.event_details.create!(
                        data: "[#{Time.now.strftime("%F %T")}] Restoring snapshot from source volume",
                        event_code: "79e6e2d3860d1806"
                      )
                    else
                      event.event_details.create!(
                        data: "[#{Time.now.strftime("%F %T")}] Creating snapshot of source volume",
                        event_code: "67e93090ab029cf5"
                      )
                    end

      source_snapshot_id = source_snapshot.blank? ? nil : Base64.decode64(source_snapshot)

      clone_name = nil
      delete_snapshot = false

      # Check if a snapshot was created in the last 10 minutes.
      # If so, use that rather than cloning fresh.
      if source_snapshot_id.nil?
        snap = source_volume.list_archives.sort_by { |i| i[:created] }[-1] # Grab latest snapshot
        if snap && snap[:created] > 10.minutes.ago
          clone_event.update data: "[#{Time.now.strftime("%F %T")}] Found recent snapshot #{snap[:label]}, skipping snapshot.\n#{clone_event.data}"
          source_snapshot_id = Base64.decode64(snap[:id])
          clone_name = snap[:label]
        end
      end

      unless source_snapshot_id

        clone_name = SecureRandom.hex(8)
        unless source_volume.create_backup!(clone_name)
          clone_event.update data: "[#{Time.now.strftime("%F %T")}] Fatal error scheduling snapshot.\n#{clone_event.data}"
          return false
        end

        delete_snapshot = true

        failed_backup_event_code = "7704f466b97ac18c"
        failed_restore_event_code = "9858861ab2912307"

        # Allow 5 minutes...
        # If the snapshot is never created, it will hit the timeout rescue block
        Timeout::timeout(300) do
          loop do
            clone_backup_event = ActiveRecord::Base.uncached { event.audit.event_logs.find_by(locale: "volume.backup") }
            if clone_backup_event # may not exist yet!
              unless clone_backup_event.active?
                if clone_backup_event.success?
                  clone_event.update data: "[#{Time.now.strftime("%F %T")}] Successfully created snapshot #{clone_name} from #{source_volume.csrn}.\n#{clone_event.data}"
                  break
                end
                clone_event.update data: "[#{Time.now.strftime("%F %T")}] Error creating backup of source volume.\n#{clone_event.data}"
                event.event_details.create!(
                  data: "Fatal error generating backup. See event log ID: #{clone_backup_event.id}",
                  event_code: failed_backup_event_code
                )
                break
              end
            end
            sleep 2
          end
        end

        return false if ActiveRecord::Base.uncached { event.event_details.where(event_code: failed_backup_event_code).exists? }

        # Grab ID of newly created snapshot
        Timeout::timeout(300) do
          loop do
            snap = source_volume.list_archives.select { |i| i[:label] == clone_name }.first
            if snap
              source_snapshot_id = Base64.decode64 snap[:id]
              break
            end
            sleep 2
          end
        end
      end

      clone_event.update data: "[#{Time.now.strftime("%F %T")}] Restoring snapshot #{clone_name} from #{source_volume.csrn}\n#{clone_event.data}."

      # Now restore the snapshot to the new volume
      volume.restore_backup! source_snapshot_id, source_volume.name

      # Wait for restore event to take place
      Timeout::timeout(300) do
        loop do
          clone_restore_event = ActiveRecord::Base.uncached { event.audit.event_logs.find_by(locale: "volume.restore") }
          if clone_restore_event # may not exist yet!
            unless clone_restore_event.active?
              break if clone_restore_event.success?
              clone_event.update data: "[#{Time.now.strftime("%F %T")}] Error restoring backup of source volume.\n#{clone_event.data}"
              event.event_details.create!(
                data: "Fatal error generating restore. See event log ID: #{clone_restore_event.id}",
                event_code: failed_restore_event_code
              )
              break
            end
          end
          sleep 2
        end
      end

      # Delete snapshot and this job is not dependent on the success or failure of this.
      source_volume.delete_backup!(source_snapshot_id) if delete_snapshot

      return false if ActiveRecord::Base.uncached { event.event_details.where(event_code: failed_restore_event_code).exists? }
      true
    rescue Timeout::Error
      if defined?(clone_name)
        clone_event.update data: "[#{Time.now.strftime("%F %T")}] Timeout reached while cloning source volume.\n#{clone_event.data}"
      end
      false
    rescue => e
      ExceptionAlertService.new(e, 'b4e181611d7c5423').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume&.inspect,
          error: e.message
        },
        event_code: 'b4e181611d7c5423'
      )
      event.event_details.create!(data: e.message, event_code: "b4e181611d7c5423") if event
      false
    end

  end
end
