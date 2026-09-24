module VolumeWorkers
  ##
  # Delete the TEMPORARY borg archive a clone took of its source volume.
  #
  # Only ever acts on a job that owns its snapshot (`owns_snapshot == true`, i.e. this clone
  # created the archive itself). The three fast paths — caller-supplied archive, reused recent
  # archive, archive adopted from a sibling clone — leave `owns_snapshot` false precisely so a
  # user's real backup can never be deleted from here.
  #
  # Enqueued only by VolumeWorkers::CloneSweepWorker, once per tick, for every id in
  # `VolumeCloneJob.needs_snapshot_cleanup`. That scope is `terminal AND owns_snapshot AND
  # snapshot_trashed_at IS NULL AND next_cleanup_at <= now`, so the ONLY things that stop the
  # 15s sweep from re-enqueuing this worker forever are stamping `snapshot_trashed_at` or
  # pushing `next_cleanup_at` into the future. Every exit path below therefore does one or the
  # other — a plain `return` would turn this into a hot loop that mints a fresh `backup.delete`
  # agent task (and a failed EventLog) four times a minute, indefinitely.
  #
  # `retry: 2` covers only a crash before we get to record the outcome on the row; the durable
  # retry mechanism is `cleanup_attempts` + `next_cleanup_at`, not Sidekiq's.
  class TrashCloneSnapshotWorker
    include Sidekiq::Worker

    sidekiq_options queue: "low", retry: 2

    # Exponential backoff between cleanup attempts, capped. With MAX_CLEANUP_ATTEMPTS = 6 the
    # schedule is: immediate, +1h, +2h, +4h, +8h, +12h, then give up (~27h of trying). Long
    # enough to ride out a node that is down for a working day, short enough that the archive
    # does not sit around billing storage for a week.
    BACKOFF_CAP = 12.hours

    # @param clone_job_id [Integer] VolumeCloneJob#id
    def perform(clone_job_id)
      job = VolumeCloneJob.find_by id: clone_job_id
      return if job.nil?
      return unless job.owns_snapshot
      return unless job.snapshot_trashed_at.nil?

      begin
        trash!(job)
      rescue => e
        ExceptionAlertService.new(e, "f47afd99e4492a09").perform
        back_off!(job, job.archive_name || job.clone_label)
      end
    end

    private

    def trash!(job)
      volume = job.source_volume
      archive = resolve_archive(job, volume)

      # Nothing to delete. Either the source volume is gone (its repository went with it), or
      # the label matches no archive on the repo — which is positive proof the backup never
      # landed, not a transient failure. Retrying can only ever produce the same answer, so
      # close the job out instead of burning 6 attempts on it.
      if volume.nil? || archive.blank?
        job.update!(snapshot_trashed_at: Time.now, next_cleanup_at: nil)
        return
      end

      # Persist the resolved raw archive name (never Base64) so a later attempt does not have
      # to re-derive it from the label.
      job.update!(archive_name: archive) if job.archive_name != archive

      # An adopter is still restoring FROM this archive. Adoption exists so one backup can
      # serve N clones, and SOURCE_CLAIM_STATES deliberately excludes the restore states so
      # adopters run in parallel with us — which means an adopter can still be gated behind
      # the per-node borg cap, or partway through a 24h restore, long after our own +2h
      # cleanup comes due. Deleting the archive here fails their restore.
      #
      # Wait without burning an attempt: working jobs are bounded (the sweeper force-
      # terminates anything past its deadline), so this cannot defer forever.
      if adopters_still_working?(job, archive)
        job.update!(next_cleanup_at: 1.hour.from_now)
        return
      end

      if volume.delete_backup!(archive)
        job.update!(snapshot_trashed_at: Time.now, next_cleanup_at: nil)
      else
        # No online node / no active node / rejected dispatch. Transient — back off and retry.
        back_off!(job, archive)
      end
    end

    # `archive_name` is set once the clone discovered the raw "<label>-m-<ts>" name the agent
    # chose. If we terminated before that (e.g. deadline blew while awaiting the backup) the
    # archive may still exist under our label, so look it up. reset_repo_info! is mandatory:
    # Volumes::ConsulVolume memoizes `repo_info`, and this object may have been used to read it
    # already — that stale memo is the exact bug that broke the old synchronous clone.

    # Any still-working clone restoring from this exact archive.
    #
    # @return [Boolean]
    def adopters_still_working?(job, archive)
      return false if archive.blank?
      VolumeCloneJob.working
        .where(source_volume_id: job.source_volume_id, archive_name: archive)
        .where.not(id: job.id)
        .exists?
    end

    def resolve_archive(job, volume)
      return job.archive_name if job.archive_name.present?
      return nil if volume.nil? || job.clone_label.blank?

      volume.reset_repo_info!.find_archive_by_label(job.clone_label)
    end

    def back_off!(job, archive)
      attempts = job.cleanup_attempts + 1

      if attempts >= VolumeCloneJob::MAX_CLEANUP_ATTEMPTS
        job.update!(cleanup_attempts: attempts, snapshot_trashed_at: Time.now, next_cleanup_at: nil)
        record_abandoned_snapshot(job, archive)
      else
        job.update!(cleanup_attempts: attempts, next_cleanup_at: Time.now + backoff_for(attempts))
      end
    end

    def backoff_for(attempts)
      [2**(attempts - 1), BACKOFF_CAP / 1.hour].min.hours
    end

    # Terminal, and it needs a durable record rather than a log line inside a Sidekiq
    # container: we are stamping `snapshot_trashed_at` on an archive that is still on disk, so
    # nothing will ever look at it again. Someone has to be told which archive on which volume
    # to reap by hand. Fires at most once per clone job, so no dedup is needed.
    #
    # Shares the frozen "abandoned snapshot" code with
    # VolumeServices::CloneStepService::ABANDONED_SNAPSHOT_EVENT_CODE (the other way a clone can
    # leave an archive behind: terminating before it ever learned the archive's name). Literal,
    # not a reference to that constant, because the code — not the constant — is the contract.
    def record_abandoned_snapshot(job, archive)
      volume = job.source_volume
      SystemEvent.create!(
        message: "Abandoned clone snapshot #{archive.inspect} on volume #{volume&.name || "(deleted)"} " \
                 "after #{VolumeCloneJob::MAX_CLEANUP_ATTEMPTS} failed cleanup attempts; delete it manually.",
        log_level: "warn",
        event_code: "0b93af5162c7de84",
        audit_id: job.audit_id,
        data: {
          "clone_job_id" => job.id,
          "archive" => archive,
          "source_volume_id" => job.source_volume_id,
          "volume_id" => job.volume_id
        }
      )
    end
  end
end
