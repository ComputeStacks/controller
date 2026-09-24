##
# One volume's data clone, as a durable state machine.
#
# Created by VolumeServices::EnqueueCloneService when an order provisions a volume with
# `action: "clone"`, advanced by VolumeServices::CloneStepService, and driven by
# VolumeWorkers::CloneSweepWorker on a 15s clock. The row is the ONLY durable state — the
# workers hold nothing — so the machine survives SIGKILL, a Redis flush, and a full restart.
#
# The EventLogs it creates are purely presentational; this row is authoritative. If a reaper
# terminates an event out from under a live job (see Events::EventPurger#clean_event_status!),
# the machine keeps going and records the discrepancy rather than losing the clone.
#
# @!attribute state
#   @return [String] one of WORKING_STATES + TERMINAL_STATES
# @!attribute owns_snapshot
#   @return [Boolean] true only when WE created the archive, and therefore must trash it. False
#     on all three fast paths (caller-supplied archive, reused recent archive, adopted from a
#     sibling) so a user's real backup is never deleted.
class VolumeCloneJob < ApplicationRecord
  belongs_to :volume, optional: true
  belongs_to :source_volume, class_name: "Volume", optional: true
  belongs_to :audit, optional: true
  belongs_to :deployment, optional: true
  belongs_to :order, optional: true
  belongs_to :node, optional: true
  belongs_to :event_log, optional: true

  # Waiting for the owning container to be built before the restore can land in its mount.
  STATE_AWAITING_CONTAINER = "awaiting_container"
  # Deciding between the three fast paths and a fresh backup.
  STATE_RESOLVING_SOURCE = "resolving_source"
  STATE_DISPATCHING_BACKUP = "dispatching_backup"
  STATE_AWAITING_BACKUP = "awaiting_backup"
  # Backup completed; find the raw "<label>-m-<ts>" name the agent chose.
  STATE_DISCOVERING_ARCHIVE = "discovering_archive"
  STATE_DISPATCHING_RESTORE = "dispatching_restore"
  STATE_AWAITING_RESTORE = "awaiting_restore"

  STATE_PENDING = "pending"
  STATE_COMPLETED = "completed"
  STATE_FAILED = "failed"
  STATE_CANCELLED = "cancelled"

  WORKING_STATES = [
    STATE_PENDING,
    STATE_AWAITING_CONTAINER,
    STATE_RESOLVING_SOURCE,
    STATE_DISPATCHING_BACKUP,
    STATE_AWAITING_BACKUP,
    STATE_DISCOVERING_ARCHIVE,
    STATE_DISPATCHING_RESTORE,
    STATE_AWAITING_RESTORE
  ].freeze

  TERMINAL_STATES = [STATE_COMPLETED, STATE_FAILED, STATE_CANCELLED].freeze

  # States in which this job holds the same-source claim: a sibling cloning from the same
  # source must wait, and will then adopt this job's archive_name instead of taking its own
  # backup. (Note DISPATCHING_RESTORE and AWAITING_RESTORE are absent — once the archive
  # exists, siblings can adopt it and proceed in parallel.)
  SOURCE_CLAIM_STATES = [
    STATE_DISPATCHING_BACKUP,
    STATE_AWAITING_BACKUP,
    STATE_DISCOVERING_ARCHIVE
  ].freeze

  # Per-state absolute budgets, measured from `entered_state_at`. Gated time is excluded (see
  # #release_gate!), but nothing else extends them: the two awaiting_* states are bounded by
  # the flat 12h / 24h below, generous enough for a large volume. A true stall extension
  # ("no progress for N hours" rather than "N hours total") is deliberately not implemented —
  # see CloneStepService#reassert_state_budget!.
  STATE_DEADLINES = {
    STATE_PENDING => 5.minutes,
    STATE_AWAITING_CONTAINER => 30.minutes,
    STATE_RESOLVING_SOURCE => 5.minutes,
    STATE_DISPATCHING_BACKUP => 30.minutes,
    STATE_AWAITING_BACKUP => 12.hours,
    STATE_DISCOVERING_ARCHIVE => 15.minutes,
    STATE_DISPATCHING_RESTORE => 30.minutes,
    STATE_AWAITING_RESTORE => 24.hours
  }.freeze

  # How long a failed clone keeps its banner / red row label. Terminal rows outlive the clone
  # by design (the snapshot reaper and post-mortems both need them), so without a window a
  # clone that failed months ago would still be shouting at the customer on the project page.
  UI_FAILURE_WINDOW = 24.hours

  # Consecutive raising ticks before the sweeper forces this job terminal.
  MAX_CONSECUTIVE_ERRORS = 5

  # Longest a job may sit blocked on a gate before it gives up. Lives here, not in
  # CloneStepService, because the `overdue` scope below has to honour the same exemption the
  # in-tick deadline check does.
  MAX_GATED_TIME = 6.hours
  # Attempts before TrashCloneSnapshotWorker gives up and stamps snapshot_trashed_at anyway.
  MAX_CLEANUP_ATTEMPTS = 6

  validates :state, inclusion: {in: WORKING_STATES + TERMINAL_STATES}

  scope :working, -> { where(state: WORKING_STATES) }
  scope :terminal, -> { where(state: TERMINAL_STATES) }
  scope :due, -> { working.where(next_poll_at: ..Time.now) }
  # Force-terminated by the sweeper rather than in-tick, so a tick that raises every time
  # still reaches the terminal funnel (and schedules its snapshot cleanup).
  #
  # Gated jobs within MAX_GATED_TIME are exempt, mirroring CloneStepService#enforce_deadline!.
  # A gated job's deadline is only pushed forward by its own ticks, and ticks run on `dep_low`
  # while this sweeper runs on `dep_critical` — so under a deployment-queue backlog the sweeper
  # stays healthy while ticks stall, and without this exemption it would force-fail a follower
  # that was correctly waiting its turn behind a sibling's backup. MAX_GATED_TIME is what
  # actually bounds a gate; CloneStepService#gated! enforces it.
  scope :overdue, lambda {
    ungated_and_expired = working
      .where.not(state_deadline_at: nil).where(state_deadline_at: ...Time.now)
      .where("volume_clone_jobs.gate_blocked_since IS NULL OR volume_clone_jobs.gate_blocked_since < ?",
        MAX_GATED_TIME.ago)
    ungated_and_expired.or(working.where(consecutive_errors: MAX_CONSECUTIVE_ERRORS..))
  }
  scope :needs_snapshot_cleanup, lambda {
    terminal.where(owns_snapshot: true, snapshot_trashed_at: nil)
      .where(next_cleanup_at: ..Time.now)
  }
  scope :recently_failed, lambda {
    where(state: STATE_FAILED).where(finished_at: UI_FAILURE_WINDOW.ago..)
  }
  # What the project page and the volume list surface: everything still in flight, plus
  # failures recent enough to still be news. Deliberately NOT driven off the umbrella
  # EventLog — a reaper can terminate that event out from under a live job, and this row is
  # the authoritative one.
  scope :surfaced, -> { working.or(recently_failed) }

  def working? = WORKING_STATES.include?(state)

  def terminal? = TERMINAL_STATES.include?(state)

  def gated? = gate_blocked_since.present?

  # Move to `new_state`, resetting the per-state counters and setting a fresh deadline.
  # Clears the gate marker: entering a state is, by definition, no longer being blocked from it.
  def enter_state!(new_state, poll_in: 0.seconds)
    now = Time.now
    update!(
      state: new_state,
      entered_state_at: now,
      state_deadline_at: STATE_DEADLINES[new_state] ? now + STATE_DEADLINES[new_state] : nil,
      next_poll_at: now + poll_in,
      attempts: 0,
      dispatch_attempts: 0,
      consecutive_errors: 0,
      gate_blocked_since: nil,
      gate_reason: nil
    )
  end

  # Push the deadline out by the time spent gated, so a legitimate wait never expires a state.
  # Called when a gate that was blocking us opens.
  def release_gate!
    return if gate_blocked_since.nil?
    blocked_for = Time.now - gate_blocked_since
    update!(
      gate_blocked_since: nil,
      gate_reason: nil,
      state_deadline_at: state_deadline_at ? state_deadline_at + blocked_for : nil
    )
  end
end
