module VolumeWorkers
  ##
  # Advance ONE VolumeCloneJob by exactly one step. Enqueued only by
  # VolumeWorkers::CloneSweepWorker (never by itself, never by the service) for every id in
  # `VolumeCloneJob.due`; the row — not Redis — is the durable state, so a lost or killed job
  # costs at most one 15s tick.
  #
  # `retry: 1` rather than `false` covers a transient DB blip on the way in; a genuinely
  # failing tick is not something retries fix — CloneStepService records the error on the row
  # (`consecutive_errors`), and the sweeper force-terminates at MAX_CONSECUTIVE_ERRORS.
  #
  # == Why there is deliberately NO sidekiq-unique-jobs `lock:` here
  #
  # This looks like an omission — most of the fan-out workers in this app carry one — so, to
  # save the next reader the archaeology: mutual exclusion for a clone job is the
  # `job.with_lock` row lock inside CloneStepService (the same idiom as
  # Agent::TaskReconciler#react), and a Redis lock on top of it would be strictly worse.
  # Verified against the installed sidekiq-unique-jobs 8.1.0:
  #
  #   * `OnConflict::Reject` does not drop a conflicting job, it pushes it to the Sidekiq
  #     DEAD SET. A clone that loses one race would sit in the morgue rather than simply
  #     being re-dispatched by the next sweep.
  #   * `UntilExecuted` releases the lock only after `yield` returns. Production runs Sidekiq
  #     under supervisord with `stopsignal=KILL` (lib/build/supervisord.conf), so a worker
  #     killed mid-tick never reaches the unlock and orphans its digest — recovery then waits
  #     on the 600s reaper, i.e. up to 10 minutes of a stalled clone, per job.
  #
  # A Postgres row lock has neither problem: it is released by the transaction ending, which a
  # SIGKILL guarantees (the backend dies, the transaction rolls back), and the next tick simply
  # takes the lock. Duplicate concurrent ticks are therefore harmless-by-construction — the
  # loser serializes on the row and re-reads the state before deciding anything.
  class CloneStepWorker
    include Sidekiq::Worker

    sidekiq_options queue: "dep_low", retry: 1

    # @param clone_job_id [Integer] VolumeCloneJob#id (Sidekiq.strict_args! — Integer, not a
    #   GlobalID or a String)
    def perform(clone_job_id)
      job = VolumeCloneJob.find_by id: clone_job_id
      return if job.nil?
      # Raced with the sweeper's force-terminate, or a sibling adopted us: nothing to do.
      return if job.terminal?

      VolumeServices::CloneStepService.new(job).perform
    rescue => e
      ExceptionAlertService.new(e, "3f2907a167443f58").perform
    end
  end
end
