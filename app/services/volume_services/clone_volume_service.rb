module VolumeServices
  class CloneVolumeService

    attr_accessor :volume,
                  :source_volume,
                  :source_snapshot,
                  :event,
                  :errors

    # @param [Volume] vol
    # @param [EventLog] event
    def initialize(vol, event)
      self.volume = vol
      self.event = event
      self.source_volume = nil
      self.source_snapshot = nil
      self.errors = []
    end

    def perform
      return false unless container_ready?
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
      volume.current_audit = event.audit
      source_volume.current_audit = event.audit

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

      if source_snapshot_id.blank?
        clone_event.update data: "[#{Time.now.strftime("%F %T")}] Fatal error restoring backup. Expected #{clone_name}, found ''.\n#{clone_event.data}."
        return false
      end

      clone_event.update data: "[#{Time.now.strftime("%F %T")}] Restoring snapshot #{clone_name} from #{source_volume.csrn}\n#{clone_event.data}."

      # Now restore the snapshot to the new volume
      unless volume.restore_backup!(source_snapshot_id, source_volume.name)
        clone_event.update data: "[#{Time.now.strftime("%F %T")}] Fatal Error while restoring snapshot #{clone_name} from #{source_volume.csrn}\n#{clone_event.data}."
        return false
      end

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

      if delete_snapshot
        VolumeWorkers::TrashSnapshotWorker.perform_in 2.hours, source_volume.id, source_snapshot_id
      end

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

    private

    # @return Boolean
    def container_ready?
      # Ensure container is built (with timeout to wait)
      if volume.owner.nil?
        errors << "Missing Container Service, unable to clone volume."
        return false
      end

      return true if volume.owner.containers.first&.built?

      # Wait for container to be built, may need a bit more time.
      Timeout::timeout(90) do
        loop do
          built = ActiveRecord::Base.uncached { volume.owner.containers.first&.built? }
          break if built
          sleep 2
        end
      end

      true
    rescue Timeout::Error
      event.event_details.create!(
        data: "[#{Time.now.strftime("%F %T")}] Timeout reached while waiting for container to be created.",
        event_code: "53a075e943b51b72"
      )
      false
    rescue => e
      ExceptionAlertService.new(e, 'e9f32956526b8c45').perform
      SystemEvent.create!(
        message: "Error creating volume.",
        log_level: "warn",
        data: {
          volume: volume&.inspect,
          error: e.message
        },
        event_code: 'e9f32956526b8c45'
      )
      event.event_details.create!(data: e.message, event_code: "e9f32956526b8c45") if event
      false
    end

  end
end
