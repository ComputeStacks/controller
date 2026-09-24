require "test_helper"

##
# The durable state of one async volume clone. Everything the sweeper and
# VolumeServices::CloneStepService rely on lives here: which rows are pickable (`due`),
# which are past saving (`overdue`), which still own a snapshot that must be trashed
# (`needs_snapshot_cleanup`), and the two writers — `enter_state!` (fresh budget, counters
# zeroed, gate cleared) and `release_gate!` (the deadline must move by exactly the time
# spent blocked, or a follower behind a legitimate 40 minute backup dies of its own
# 30 minute dispatch budget).
#
# NB there is no volume_clone_jobs fixture, so every scope assertion below sees only the
# rows the test itself created.
class VolumeCloneJobTest < ActiveSupport::TestCase
  include CloneTestHelpers

  # --- constants -----------------------------------------------------------------------

  test "working and terminal states are disjoint and cover the validated set" do
    assert_empty VolumeCloneJob::WORKING_STATES & VolumeCloneJob::TERMINAL_STATES
    assert_equal (VolumeCloneJob::WORKING_STATES + VolumeCloneJob::TERMINAL_STATES).sort,
      VolumeCloneJob.validators_on(:state).first.options[:in].sort
  end

  test "every working state carries a deadline budget and no terminal state does" do
    VolumeCloneJob::WORKING_STATES.each do |state|
      assert VolumeCloneJob::STATE_DEADLINES[state].present?,
        "#{state} has no STATE_DEADLINES budget — VolumeCloneJob.overdue can never see it"
    end
    VolumeCloneJob::TERMINAL_STATES.each do |state|
      assert_nil VolumeCloneJob::STATE_DEADLINES[state]
    end
  end

  test "the same-source claim states are a subset of the working states" do
    assert_equal VolumeCloneJob::SOURCE_CLAIM_STATES,
      VolumeCloneJob::SOURCE_CLAIM_STATES & VolumeCloneJob::WORKING_STATES
  end

  # --- working / terminal --------------------------------------------------------------

  test "working scope and predicate match every working state" do
    job = make_clone_job

    VolumeCloneJob::WORKING_STATES.each do |state|
      job.update!(state: state)
      assert job.working?, "#{state} should be working?"
      assert_not job.terminal?, "#{state} should not be terminal?"
      assert_includes VolumeCloneJob.working, job
      assert_not_includes VolumeCloneJob.terminal, job
    end
  end

  test "terminal scope and predicate match every terminal state" do
    job = make_clone_job

    VolumeCloneJob::TERMINAL_STATES.each do |state|
      job.update!(state: state)
      assert job.terminal?, "#{state} should be terminal?"
      assert_not job.working?, "#{state} should not be working?"
      assert_includes VolumeCloneJob.terminal, job
      assert_not_includes VolumeCloneJob.working, job
    end
  end

  # --- due -----------------------------------------------------------------------------

  test "due includes a working job whose poll time has arrived and excludes one in the future" do
    travel_to Time.now do
      job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP, next_poll_at: 1.second.ago)
      assert_includes VolumeCloneJob.due, job

      # Boundary: the range is inclusive of "now".
      job.update!(next_poll_at: Time.now)
      assert_includes VolumeCloneJob.due, job

      job.update!(next_poll_at: 1.second.from_now)
      assert_not_includes VolumeCloneJob.due, job
    end
  end

  test "due never returns a terminal job even when its poll time has passed" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP, next_poll_at: 1.hour.ago)
    assert_includes VolumeCloneJob.due, job

    VolumeCloneJob::TERMINAL_STATES.each do |state|
      job.update!(state: state)
      assert_not_includes VolumeCloneJob.due, job, "#{state} must never be due"
    end
  end

  # --- overdue -------------------------------------------------------------------------

  test "overdue ignores a job with no deadline and one whose deadline has not passed" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP, state_deadline_at: nil)
    assert_not_includes VolumeCloneJob.overdue, job

    job.update!(state_deadline_at: 1.minute.from_now)
    assert_not_includes VolumeCloneJob.overdue, job
  end

  test "overdue picks up a working job whose deadline has passed, exclusive of now" do
    travel_to Time.now do
      job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, state_deadline_at: Time.now)
      # `...Time.now` is an exclusive range: a deadline of exactly now has not passed yet.
      assert_not_includes VolumeCloneJob.overdue, job

      job.update!(state_deadline_at: 1.second.ago)
      assert_includes VolumeCloneJob.overdue, job
    end
  end

  test "overdue picks up a job that has raised MAX_CONSECUTIVE_ERRORS times in a row" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      state_deadline_at: 1.hour.from_now,
      consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS - 1)
    assert_not_includes VolumeCloneJob.overdue, job

    job.update!(consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS)
    assert_includes VolumeCloneJob.overdue, job

    job.update!(consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS + 3)
    assert_includes VolumeCloneJob.overdue, job
  end

  test "overdue never returns a terminal job" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      state_deadline_at: 1.hour.ago,
      consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS)
    assert_includes VolumeCloneJob.overdue, job

    VolumeCloneJob::TERMINAL_STATES.each do |state|
      job.update!(state: state)
      assert_not_includes VolumeCloneJob.overdue, job, "#{state} must never be overdue"
    end
  end

  # --- needs_snapshot_cleanup ----------------------------------------------------------

  def cleanup_candidate(**attrs)
    defaults = {
      state: VolumeCloneJob::STATE_COMPLETED,
      owns_snapshot: true,
      snapshot_trashed_at: nil,
      next_cleanup_at: 1.minute.ago,
      archive_name: archive_name("clone-cleanup")
    }
    make_clone_job(**defaults.merge(attrs))
  end

  test "needs_snapshot_cleanup finds a terminal job that still owns an untrashed snapshot" do
    job = cleanup_candidate
    assert_includes VolumeCloneJob.needs_snapshot_cleanup, job

    # A failure keeps its snapshot too — the only forensic artifact of a failed clone.
    job.update!(state: VolumeCloneJob::STATE_FAILED)
    assert_includes VolumeCloneJob.needs_snapshot_cleanup, job
    job.update!(state: VolumeCloneJob::STATE_CANCELLED)
    assert_includes VolumeCloneJob.needs_snapshot_cleanup, job
  end

  test "needs_snapshot_cleanup skips a job that is still working" do
    job = cleanup_candidate
    VolumeCloneJob::WORKING_STATES.each do |state|
      job.update!(state: state)
      assert_not_includes VolumeCloneJob.needs_snapshot_cleanup, job, "#{state} is not terminal"
    end
  end

  test "needs_snapshot_cleanup skips a job that does not own its snapshot" do
    # The three fast paths (caller-supplied / recent / adopted archive) leave owns_snapshot
    # false precisely so a real user backup is never trashed.
    job = cleanup_candidate(owns_snapshot: false)
    assert_not_includes VolumeCloneJob.needs_snapshot_cleanup, job
  end

  test "needs_snapshot_cleanup skips a snapshot that has already been trashed" do
    job = cleanup_candidate(snapshot_trashed_at: 1.minute.ago)
    assert_not_includes VolumeCloneJob.needs_snapshot_cleanup, job
  end

  test "needs_snapshot_cleanup respects next_cleanup_at" do
    travel_to Time.now do
      job = cleanup_candidate(next_cleanup_at: 1.second.from_now)
      assert_not_includes VolumeCloneJob.needs_snapshot_cleanup, job

      job.update!(next_cleanup_at: Time.now)
      assert_includes VolumeCloneJob.needs_snapshot_cleanup, job
    end
  end

  test "needs_snapshot_cleanup skips a job with no cleanup scheduled at all" do
    job = cleanup_candidate(next_cleanup_at: nil)
    assert_not_includes VolumeCloneJob.needs_snapshot_cleanup, job
  end

  # --- enter_state! --------------------------------------------------------------------

  test "enter_state! stamps the state, its deadline and resets the per-state counters" do
    now = Time.now.change(usec: 0)
    travel_to now do
      job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE,
        entered_state_at: 1.hour.ago,
        attempts: 7, dispatch_attempts: 3, consecutive_errors: 4,
        gate_blocked_since: 20.minutes.ago, gate_reason: "node is at its limit")

      job.enter_state!(VolumeCloneJob::STATE_AWAITING_BACKUP)
      job.reload

      assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
      assert_equal now, job.entered_state_at
      assert_equal now + VolumeCloneJob::STATE_DEADLINES[VolumeCloneJob::STATE_AWAITING_BACKUP],
        job.state_deadline_at
      assert_equal now, job.next_poll_at
      assert_equal 0, job.attempts
      assert_equal 0, job.dispatch_attempts
      assert_equal 0, job.consecutive_errors
      assert_nil job.gate_blocked_since
      assert_nil job.gate_reason
      assert_not job.gated?
    end
  end

  test "enter_state! sets the deadline from STATE_DEADLINES for every working state" do
    now = Time.now.change(usec: 0)
    travel_to now do
      job = make_clone_job
      VolumeCloneJob::WORKING_STATES.each do |state|
        job.enter_state!(state)
        job.reload
        assert_equal now + VolumeCloneJob::STATE_DEADLINES[state], job.state_deadline_at,
          "wrong deadline for #{state}"
      end
    end
  end

  test "enter_state! honours poll_in without touching the deadline" do
    now = Time.now.change(usec: 0)
    travel_to now do
      job = make_clone_job
      job.enter_state!(VolumeCloneJob::STATE_DISCOVERING_ARCHIVE, poll_in: 30.seconds)
      job.reload

      assert_equal now + 30.seconds, job.next_poll_at
      assert_equal now + VolumeCloneJob::STATE_DEADLINES[VolumeCloneJob::STATE_DISCOVERING_ARCHIVE],
        job.state_deadline_at
    end
  end

  test "enter_state! leaves the deadline nil for a state with no budget" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE)
    assert_not_nil job.state_deadline_at

    job.enter_state!(VolumeCloneJob::STATE_COMPLETED)
    assert_nil job.reload.state_deadline_at
  end

  # --- release_gate! -------------------------------------------------------------------

  test "release_gate! pushes the deadline out by exactly the time spent blocked" do
    now = Time.now.change(usec: 0)
    travel_to now do
      job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
        state_deadline_at: now + 10.minutes,
        gate_blocked_since: now - 20.minutes,
        gate_reason: "another clone is snapshotting the same source volume")
      assert job.gated?

      job.release_gate!
      job.reload

      assert_equal now + 30.minutes, job.state_deadline_at
      assert_nil job.gate_blocked_since
      assert_nil job.gate_reason
      assert_not job.gated?
    end
  end

  test "release_gate! is a no-op when the job was never gated" do
    now = Time.now.change(usec: 0)
    travel_to now do
      job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
        state_deadline_at: now + 10.minutes)
      assert_not job.gated?
      before = job.updated_at

      assert_nil job.release_gate!
      job.reload

      assert_equal now + 10.minutes, job.state_deadline_at
      assert_equal before, job.updated_at, "release_gate! must not write when nothing was blocked"
    end
  end

  test "release_gate! clears the gate without inventing a deadline" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      state_deadline_at: nil, gate_blocked_since: 5.minutes.ago, gate_reason: "waiting")

    job.release_gate!
    job.reload

    assert_nil job.state_deadline_at
    assert_nil job.gate_blocked_since
    assert_not job.gated?
  end
end
