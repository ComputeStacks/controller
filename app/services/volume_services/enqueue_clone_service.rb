module VolumeServices
  ##
  # Turn an order's `volume_clones` list into durable VolumeCloneJob rows and hand them to the
  # async state machine (VolumeServices::CloneStepService, driven by
  # VolumeWorkers::CloneSweepWorker).
  #
  # This replaces the inline blocking clone loop in DeployServices::DeployProjectService, which
  # ran Timeout+sleep loops of up to ~46 minutes PER VOLUME, serially, inside ProcessOrderWorker.
  # Everything here is microseconds: resolve, validate, insert, enqueue.
  #
  # Only structural problems — an order-data bug we can detect immediately — go into `errors`
  # and thereby fail the order. Anything that can only be discovered by talking to a node is the
  # state machine's business and surfaces on the per-volume clone event instead; a clone failure
  # must never reach ProcessOrderService#fail_process!, which detaches the project's private
  # network.
  #
  # @!attribute project
  #   @return [Deployment]
  # @!attribute event
  #   @return [EventLog] the order's provision event
  # @!attribute volume_clones
  #   @return [Array<Hash>] [{ vol_id:, source_vol_id:, source_snap: }]
  # @!attribute jobs
  #   @return [Array<VolumeCloneJob>] rows created or reused, in input order
  # @!attribute errors
  #   @return [Array<String>]
  class EnqueueCloneService
    attr_accessor :project,
      :event,
      :volume_clones,
      :jobs,
      :errors

    # @param [Deployment] project
    # @param [EventLog] event
    # @param [Array<Hash>] volume_clones
    def initialize(project, event, volume_clones)
      self.project = project
      self.event = event
      self.volume_clones = volume_clones || []
      self.jobs = []
      self.errors = []
    end

    # @return [Boolean]
    def perform
      volume_clones.each { |request| enqueue_one(request) }
      errors.empty?
    end

    private

    def enqueue_one(request)
      volume = Volume.find_by(id: request[:vol_id])
      if volume.nil?
        errors << "Volume #{request[:vol_id]} not found, unable to restore."
        return
      end

      source_volume = Volume.find_by(id: request[:source_vol_id])
      if source_volume.nil?
        errors << "Source volume #{request[:source_vol_id].inspect} not found, unable to restore #{volume.label}."
        return
      end

      # Hoisted out of the old CloneVolumeService, where it was discovered ten minutes into a
      # background job. It is a pure order-data problem, so fail the order.
      if volume.region_id != source_volume.region_id
        errors << "Cannot clone #{volume.label}: source volume is in a different availability zone."
        return
      end

      requested_archive = decode_snapshot(request[:source_snap], volume)
      return if requested_archive == :error

      job = VolumeCloneJob.find_or_create_by!(volume_id: volume.id) do |j|
        j.source_volume_id = source_volume.id
        j.deployment_id = project&.id
        j.order_id = order_id
        j.audit_id = clone_audit_for(volume)&.id
        j.requested_archive = requested_archive
        j.state = VolumeCloneJob::STATE_PENDING
        j.next_poll_at = Time.now
      end

      # `find_or_create_by!` makes us idempotent under ProcessOrderWorker's retry, but a retry
      # arriving AFTER a clone failed would otherwise see a terminal row, treat the enqueue as
      # done, and let the order complete green over a volume that was never cloned — the same
      # class of silent success as the `errors + cv.errors` bug this change exists to fix.
      # Re-arm it instead. A row still working is left strictly alone.
      rearm!(job, source_volume, requested_archive) if job.terminal?

      jobs << job
      VolumeWorkers::CloneStepWorker.perform_async job.id
    rescue => e
      ExceptionAlertService.new(e, "6d0a94c1fb3e5827").perform
      errors << "Failed to schedule clone for volume #{request[:vol_id]}: #{e.message}"
    end

    def rearm!(job, source_volume, requested_archive)
      # The previous attempt's temporary snapshot is about to become unreachable: the reaper
      # selects on `owns_snapshot`, and we are wiping it. Say so loudly before it disappears —
      # this is a real archive sitting in the customer's billed borg repo, and a silent wipe
      # leaves nothing anywhere that names it.
      #
      # KNOWN GAP: this records the orphan, it does not reap it. Reaping needs somewhere
      # durable to hold "delete this archive" independent of the clone row, and the row is
      # uniquely indexed on volume_id so the retry has to reuse it.
      orphan_snapshot!(job) if job.owns_snapshot && job.snapshot_trashed_at.nil?

      job.update!(
        source_volume_id: source_volume.id,
        deployment_id: project&.id,
        order_id: order_id,
        audit_id: clone_audit_for(job.volume)&.id,
        requested_archive: requested_archive,
        state: VolumeCloneJob::STATE_PENDING,
        next_poll_at: Time.now,
        entered_state_at: nil,
        state_deadline_at: nil,
        gate_blocked_since: nil,
        gate_reason: nil,
        clone_label: nil,
        archive_name: nil,
        owns_snapshot: false,
        backup_task_id: nil,
        backup_dispatched_at: nil,
        restore_task_id: nil,
        restore_dispatched_at: nil,
        event_log_id: nil,
        attempts: 0,
        dispatch_attempts: 0,
        consecutive_errors: 0,
        last_error: nil,
        polled_at: nil,
        started_at: nil,
        finished_at: nil,
        # Reset the cleanup bookkeeping too, or the NEW run's snapshot leaks: a stale
        # `snapshot_trashed_at` from the previous attempt makes CloneStepService#enter_terminal!
        # skip scheduling `next_cleanup_at` entirely, and a stale `cleanup_attempts` eats the
        # retry budget before the reaper has tried once.
        snapshot_trashed_at: nil,
        cleanup_attempts: 0,
        next_cleanup_at: nil
      )
    end

    # Record an owned snapshot we are about to lose track of.
    def orphan_snapshot!(job)
      archive = job.archive_name.presence || job.clone_label.presence
      return if archive.blank?
      SystemEvent.create!(
        message: "Volume clone retry orphaned a temporary snapshot: #{archive}",
        log_level: "warn",
        event_code: "0b93af5162c7de84",
        audit_id: job.audit_id,
        data: {
          "clone_job_id" => job.id,
          "source_volume_id" => job.source_volume_id,
          "archive" => job.archive_name,
          "clone_label" => job.clone_label,
          "previous_state" => job.state
        }
      )
    rescue => e
      ExceptionAlertService.new(e, "6d0a94c1fb3e5827").perform
    end

    # The order carries the snapshot id Base64-encoded (list_archives hands out
    # `Base64.urlsafe_encode64(raw)`). Decode to the RAW borg archive name, which is what
    # restore_backup! wants; never let it round-trip through Base64 again.
    #
    # @return [String, nil, :error]
    def decode_snapshot(value, volume)
      return nil if value.blank?
      begin
        Base64.urlsafe_decode64(value)
      rescue ArgumentError
        begin
          Base64.strict_decode64(value)
        rescue ArgumentError
          errors << "Cannot clone #{volume.label}: requested snapshot id is not valid."
          :error
        end
      end
    end

    # A clone gets its OWN Audit, never the order's.
    #
    # PowerCycleContainerService selects the event to drive with
    # `audit.event_logs.first if audit && audit.event_logs.count == 1`, so putting a clone's
    # EventLogs on the order audit flips every container build onto its own event. That changes
    # when the order completes, arms ProcessOrderService's `ensure` -> fail_process! (which
    # detaches the project's private network), and makes Deployment#has_failed_jobs?
    # nondeterministic. A per-volume audit also removes the shared-audit ambiguity in
    # Agent::TaskReconciler#correlated_event.
    #
    # @return [Audit, nil]
    def clone_audit_for(volume)
      return nil if volume.nil?
      @clone_audits ||= {}
      @clone_audits[volume.id] ||= Audit.create!(
        event: "restored",
        rel_id: volume.id,
        rel_model: "Volume",
        ip_addr: order_audit&.ip_addr,
        user: order_audit&.user
      )
    end

    def order_audit
      @order_audit ||= event&.audit
    end

    # The order that triggered this provisioning run, for the terminal funnel's summary line on
    # the order page. Resolved off the provision event's audit (Order#audits is
    # `rel_model: "Order"` keyed by rel_uuid), not off project.orders — a project accumulates
    # orders over its life and "the newest one" is not reliably this one.
    #
    # @return [String, nil]
    def order_id
      return @order_id if defined?(@order_id)
      @order_id = (order_audit&.rel_model == "Order") ? order_audit.rel_uuid : nil
    end
  end
end
