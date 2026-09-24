module VolumeWorkers
  ##
  # The heartbeat of the volume-clone state machine, run every 15s by Clockwork
  # ("volume.clone_sweep" in lib/clock.rb). It is the ONLY enqueuer in the design: no clone
  # worker ever re-enqueues itself, so there is exactly one place where work is created and a
  # runaway loop is impossible by construction.
  #
  # Three responsibilities, in this order:
  #
  #   1. force-terminate jobs that are out of time or out of retries;
  #   2. enqueue a step tick for every job whose next_poll_at has come due;
  #   3. enqueue snapshot cleanup for every terminal job that still owns a temporary archive.
  #
  # == Why `dep_critical` and not `dep_low`
  #
  # The step ticks it dispatches run on `dep_low`. If the sweeper shared that queue, a burst of
  # clones (an order provisioning a dozen volumes, each polling every few seconds) would put the
  # dispatcher behind its own dispatches: the sweeper would only run when the work it created
  # had drained, and the whole machine would stall exactly when it is busiest. `dep_critical`
  # has a 2x weight in config/sidekiq/deployments.yml.erb and carries no long-running work, so
  # the heartbeat stays live regardless of clone load. (`dep_critical`/`dep_low` are both
  # served by worker_deployments; `low` — used by TrashCloneSnapshotWorker — is worker_system.)
  #
  # `retry: false` on purpose: this runs again in 15 seconds. A Sidekiq retry of a sweep would
  # only duplicate a tick that is about to be scheduled anyway.
  class CloneSweepWorker
    include Sidekiq::Worker

    sidekiq_options queue: "dep_critical", retry: false

    # "State deadline exceeded" (clone contract, frozen).
    OVERDUE_EVENT_CODE = "a80f5d1c46e3b927"

    def perform
      force_terminate_overdue!
      dispatch_due_steps!
      dispatch_snapshot_cleanup!
    rescue => e
      ExceptionAlertService.new(e, "dca0bf04c6d5a8c7").perform
    end

    private

    ##
    # Deadline / consecutive-error enforcement lives HERE, in the sweeper, and deliberately NOT
    # inside the step dispatch. A tick can fail deterministically — the classic case is a
    # nil-deref on a half-destroyed object graph after the deployment or the source volume was
    # removed under a running clone — and such a tick raises before it can reach any in-tick
    # deadline check. Enforced in-tick, that job would tick, raise, be rescued, and be
    # redispatched forever: never terminal, never scheduling its snapshot cleanup (leaking the
    # archive), and paging Sentry four times a minute in perpetuity. Enforced out here, the
    # broken row is closed out by code that never touches its object graph.
    def force_terminate_overdue!
      VolumeCloneJob.overdue.find_each do |job|
        terminate!(job)
      rescue => e
        # Per-row rescue: one poisoned job must not stop the sweep from dispatching every other
        # clone's ticks (that is the failure this whole method exists to prevent).
        ExceptionAlertService.new(e, "dca0bf04c6d5a8c7").perform
      end
    end

    # Route through the service's terminal funnel so a force-terminate produces exactly the same
    # side effects as any other failure (umbrella event failed, snapshot cleanup scheduled,
    # finished_at stamped) — see invariant 5 of the clone contract: every terminal path goes
    # through CloneStepService#enter_terminal!.
    #
    # The funnel is called defensively. This method's entire reason for existing is that these
    # rows are the ones whose object graph is broken, and the funnel necessarily touches that
    # graph (umbrella event, order provision event, source volume) — so it is exactly where a
    # NoMethodError on a nil association is most likely; and if it ever raises here, the row
    # stays `overdue` and is retried — with an alert — every 15 seconds forever. So any failure
    # falls through to a graph-free UPDATE that closes the row out for good.
    def terminate!(job)
      # Re-verify under the row lock. `overdue` was evaluated by a plain query; a step worker
      # holding the lock can legitimately advance the job into a fresh state between that query
      # and this call (a backup completing at the edge of its 12h budget is exactly the case),
      # and force-failing a job that just made progress would throw away a finished backup.
      job.with_lock do
        job.reload
        return unless VolumeCloneJob.overdue.exists?(id: job.id)
      end

      VolumeServices::CloneStepService.new(job).enter_terminal!(
        VolumeCloneJob::STATE_FAILED,
        event_code: OVERDUE_EVENT_CODE,
        reason: overdue_reason(job)
      )
    rescue => e
      ExceptionAlertService.new(e, "467335294023fb4d").perform
      force_fail!(job, overdue_reason(job))
    end

    # Last-resort terminal write: touches nothing but this row (plus its own event log, whose
    # `fail!` is a no-op once the event is already terminal). Scheduling next_cleanup_at when we
    # own the snapshot is the part that must not be skipped — without it the temporary archive
    # is never enqueued for cleanup and leaks, since `needs_snapshot_cleanup` requires a
    # non-null, due next_cleanup_at. The 24h delay mirrors CloneStepService#enter_terminal!'s
    # failure policy: the temporary snapshot is the only forensic artifact of a failed clone.
    def force_fail!(job, reason)
      now = Time.now
      stuck_in = job.state
      job.update_columns(
        state: VolumeCloneJob::STATE_FAILED,
        last_error: reason,
        finished_at: job.finished_at || now,
        gate_blocked_since: nil,
        gate_reason: nil,
        next_cleanup_at: (job.owns_snapshot && job.snapshot_trashed_at.nil?) ? (now + 24.hours) : job.next_cleanup_at,
        updated_at: now
      )
      # Durable record first: EventLog#fail! fans out to perform_callback_reply!, which can
      # raise on a broken graph, and this is the row that nobody will ever look at again.
      SystemEvent.create!(
        message: "Volume clone job #{job.id} force-terminated by the sweeper: #{reason}",
        log_level: "warn",
        event_code: OVERDUE_EVENT_CODE,
        audit_id: job.audit_id,
        data: {"clone_job_id" => job.id, "state" => stuck_in, "volume_id" => job.volume_id}
      )
      job.event_log&.fail!(reason)
    end

    def overdue_reason(job)
      if job.consecutive_errors >= VolumeCloneJob::MAX_CONSECUTIVE_ERRORS
        "Clone aborted after #{job.consecutive_errors} consecutive failed attempts in state " \
          "'#{job.state}'. Last error: #{job.last_error.presence || "unknown"}"
      else
        "Clone aborted: state '#{job.state}' exceeded its #{humanized_deadline(job)} budget."
      end
    end

    # ActiveSupport::Duration#inspect ("12 hours"), NOT distance_of_time_in_words — the latter
    # reads a bare Duration as a time relative to now and renders "about 12 hours ago".
    def humanized_deadline(job)
      VolumeCloneJob::STATE_DEADLINES[job.state]&.inspect || "allotted"
    end

    ##
    # One tick per due job. NOTE: the sweeper does NOT touch `next_poll_at` — the step worker
    # advances it inside the row lock (contract invariant 7). That means a job can legitimately
    # be dispatched twice if a sweep overlaps a slow tick; the row lock in CloneStepService
    # makes the second dispatch a no-op re-read rather than a double transition, and paying for
    # that with an occasional redundant tick is much cheaper than the alternative (a sweeper
    # that pre-stamps next_poll_at would silently skip a whole poll interval every time a step
    # job is lost or its worker is killed).
    def dispatch_due_steps!
      VolumeCloneJob.due.pluck(:id).each do |id|
        CloneStepWorker.perform_async id
      end
    end

    # Terminal jobs that created their own archive and have not yet trashed it. The worker
    # itself owns the backoff (`cleanup_attempts` / `next_cleanup_at`); this scope re-offers a
    # row only once its next_cleanup_at has come due.
    def dispatch_snapshot_cleanup!
      VolumeCloneJob.needs_snapshot_cleanup.pluck(:id).each do |id|
        TrashCloneSnapshotWorker.perform_async id
      end
    end
  end
end
