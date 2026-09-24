module ImageWorkers
  ##
  # Attach one image volume template to one already-deployed container service, then advance
  # the parent cascade event's counters. Fanned out by
  # ImageWorkers::CascadeVolumeChangeWorker; the last child to finish is the one that closes
  # the parent event.
  #
  # The double-attach hole this has to survive: an admin ticks the create-time checkbox,
  # decides the fan-out has hung, and clicks the retroactive "apply to existing services"
  # button, so two children for one service run concurrently, both see no map, both validate,
  # and the service ends up with two `is_owner` maps at one path -- which makes it permanently
  # un-rebuildable (two binds with the same destination -> Docker 400 "Duplicate mount point",
  # which `build!` does not rescue), and cleaning it up afterwards means direct database work.
  #
  # That is closed by the unique index on volume_maps (container_service_id, mount_path), NOT
  # by a sidekiq-unique-jobs lock. A lock was tried and removed on purpose: `on_conflict`
  # drops the duplicate child (dead-lettered with :reject, silently with :log), so the SECOND
  # cascade's counter stays permanently short, its event never closes, and it is reaped as
  # "cancelled" two hours later. Losing the race against the index instead is strictly better
  # -- the loser rolls back cleanly and reports an honest skip, and every child still
  # finalises its own event.
  #
  # `retry: false` is deliberate. With retries, a child that raises before finalising leaves
  # the parent counter permanently short (the event is only closed 2h later by
  # Events::EventPurger), and one that retries after finalising double-counts and can close the
  # parent early. So: never raise out of #perform, always finalise exactly once, and recover
  # transient failures by re-running the idempotent retroactive cascade instead.
  class AttachVolumeToServiceWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: "dep_low"

    SUMMARY_EVENT_CODE = "0aa263f55ef85745".freeze
    MISSING_RECORD_EVENT_CODE = "2a6461ae20624ddf".freeze
    ERROR_EVENT_CODE = "b06a4bc4fb2bdc25".freeze

    # @param [Integer] volume_param_id
    # @param [Integer] service_id
    # @param [Integer] event_id
    def perform(volume_param_id, service_id, event_id)
      event = EventLog.find_by id: event_id
      volume_param = ContainerImage::VolumeParam.find_by id: volume_param_id
      service = Deployment::ContainerService.find_by id: service_id

      # A vanished param or service still has to advance the counter, otherwise the parent
      # event hangs until the 2 hour reaper cancels it.
      if event.nil?
        return nil
      elsif volume_param.nil? || service.nil?
        event.event_details.create!(
          data: "Skipped service #{service_id}: the volume template or the service no longer exists.",
          event_code: MISSING_RECORD_EVENT_CODE
        )
        return finalize! event, :skipped
      end

      result = VolumeServices::AttachTemplateVolumeService.new(volume_param, service, event).perform
      result = :failed unless %i[created skipped failed].include?(result)

      finalize! event, result
    rescue => e
      # The service already rescues everything, so reaching here means the counter update or
      # the lookups themselves broke. Report, then still try to finalise: an unfinalised child
      # is worse than a mis-attributed one.
      ExceptionAlertService.new(e, ERROR_EVENT_CODE).perform
      SystemEvent.create!(
        message: "Error cascading volume #{volume_param_id} to container service #{service_id}",
        log_level: "warn",
        data: {
          volume_param: volume_param_id,
          container_service: service_id,
          event: event_id,
          error: e.message
        },
        event_code: ERROR_EVENT_CODE
      )
      begin
        e_log = EventLog.find_by(id: event_id)
        finalize! e_log, :failed if e_log
      rescue
        nil
      end
      nil
    end

    private

    # Advance the parent counters atomically and close the event when the last child lands.
    #
    # Tolerant of Events::EventPurger#clean_event_status!, which `update_all`s any event still
    # running after 2 hours to `cancelled`; after that `done!`/`fail!` return false silently
    # (Events::StateManager guards on `active?`). The summary detail is therefore written
    # BEFORE the terminal transition so it survives a cancelled parent.
    #
    # @param [EventLog] event
    # @param [Symbol] result
    # @return [nil]
    def finalize!(event, result)
      event.with_lock do
        l = event.labels.dup
        l["completed"] = l["completed"].to_i + 1
        l[result.to_s] = l[result.to_s].to_i + 1
        event.update!(labels: l)
        if l["completed"].to_i >= l["expected"].to_i
          summary = "created: #{l["created"]}, skipped: #{l["skipped"]}, failed: #{l["failed"]}"
          event.event_details.create!(data: summary, event_code: SUMMARY_EVENT_CODE)
          l["failed"].to_i.zero? ? event.done!(summary) : event.fail!(summary)
        end
      end
      nil
    end
  end
end
