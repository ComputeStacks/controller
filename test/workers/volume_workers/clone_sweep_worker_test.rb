require "test_helper"
require "minitest/mock"

##
# The 15s heartbeat of the clone state machine, and the ONLY enqueuer in the design.
#
# Three things it must get right: dispatch ticks for due rows (and nothing else), force
# terminate rows that are out of time or out of retries, and hand terminal rows that still own
# a temporary archive to TrashCloneSnapshotWorker — while never writing `next_poll_at`
# (contract invariant 7: only the step worker advances it, inside the row lock).
class VolumeWorkers::CloneSweepWorkerTest < ActiveSupport::TestCase
  include CloneTestHelpers

  OVERDUE_CODE = "a80f5d1c46e3b927".freeze

  setup do
    VolumeWorkers::CloneStepWorker.clear
    VolumeWorkers::TrashCloneSnapshotWorker.clear
  end

  def sweep!
    VolumeWorkers::CloneSweepWorker.new.perform
  end

  def step_ids
    VolumeWorkers::CloneStepWorker.jobs.map { |j| j["args"].first }
  end

  def trash_ids
    VolumeWorkers::TrashCloneSnapshotWorker.jobs.map { |j| j["args"].first }
  end

  # --- dispatching due steps --------------------------------------------------------

  test "enqueues a step tick for due working rows only" do
    due = make_clone_job(volume: volumes(:wordpress_web), next_poll_at: 1.minute.ago)
    future = make_clone_job(volume: volumes(:nginx_web), next_poll_at: 10.minutes.from_now)
    finished = make_clone_job(volume: volumes(:user_nginx_web),
      state: VolumeCloneJob::STATE_COMPLETED, next_poll_at: 1.minute.ago)

    sweep!

    assert_equal [due.id], step_ids
    assert_not_includes step_ids, future.id
    assert_not_includes step_ids, finished.id
  end

  # Invariant 7. A sweeper that pre-stamped next_poll_at would silently skip a whole poll
  # interval every time a step job is lost or its worker is SIGKILLed.
  test "never modifies next_poll_at" do
    due = make_clone_job(volume: volumes(:wordpress_web), next_poll_at: 1.minute.ago).reload
    future = make_clone_job(volume: volumes(:nginx_web), next_poll_at: 10.minutes.from_now).reload
    overdue = make_clone_job(volume: volumes(:user_nginx_web),
      state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      state_deadline_at: 1.minute.ago, next_poll_at: 1.minute.ago).reload

    before = {due.id => due.next_poll_at, future.id => future.next_poll_at, overdue.id => overdue.next_poll_at}

    sweep!

    before.each do |id, value|
      assert_equal value, VolumeCloneJob.find(id).next_poll_at,
        "the sweeper must never write next_poll_at (invariant 7)"
    end
  end

  test "dispatches every due row, not just the first" do
    a = make_clone_job(volume: volumes(:wordpress_web), next_poll_at: 1.minute.ago)
    b = make_clone_job(volume: volumes(:nginx_web), next_poll_at: 2.minutes.ago)
    c = make_clone_job(volume: volumes(:user_nginx_web), next_poll_at: 3.minutes.ago)

    sweep!

    assert_equal [a.id, b.id, c.id].sort, step_ids.sort
  end

  # --- force-terminating overdue rows -----------------------------------------------

  test "force-terminates a row whose state deadline has passed" do
    job = make_clone_job(
      volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      entered_state_at: 13.hours.ago,
      state_deadline_at: 1.minute.ago,
      next_poll_at: 1.minute.ago
    )
    event = job.event_log

    sweep!

    job.reload
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_not_nil job.finished_at
    assert_match(/exceeded its 12 hours budget/, job.last_error)
    assert event.reload.failed?, "the umbrella event is driven to failed"
    assert_empty step_ids, "a row terminated by this sweep is not also ticked"
  end

  test "force-terminates a row that ran out of retries" do
    job = make_clone_job(
      volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS,
      last_error: "undefined method 'name' for nil",
      next_poll_at: 1.minute.ago
    )

    sweep!

    job.reload
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/5 consecutive failed attempts/, job.last_error)
    assert_match(/undefined method/, job.last_error)
  end

  test "a force-terminated row that owns its snapshot is scheduled for cleanup" do
    job = make_clone_job(
      volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_AWAITING_RESTORE,
      state_deadline_at: 1.minute.ago,
      owns_snapshot: true,
      archive_name: archive_name("clone-leak"),
      next_poll_at: 1.minute.ago
    )

    sweep!

    job.reload
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_not_nil job.next_cleanup_at, "without next_cleanup_at the archive leaks forever"
    assert_in_delta 24.hours.from_now.to_i, job.next_cleanup_at.to_i, 120
  end

  test "leaves rows that are inside their deadline alone" do
    job = make_clone_job(
      volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      state_deadline_at: 4.hours.from_now,
      consecutive_errors: VolumeCloneJob::MAX_CONSECUTIVE_ERRORS - 1,
      next_poll_at: 1.minute.ago
    )

    sweep!

    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.reload.state
    assert_equal [job.id], step_ids
  end

  # --- snapshot cleanup -------------------------------------------------------------

  test "enqueues snapshot cleanup for terminal rows that still own an archive" do
    ready = make_clone_job(volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_COMPLETED, owns_snapshot: true,
      archive_name: archive_name("done"), next_cleanup_at: 1.minute.ago)
    backing_off = make_clone_job(volume: volumes(:nginx_web),
      state: VolumeCloneJob::STATE_FAILED, owns_snapshot: true,
      archive_name: archive_name("later"), next_cleanup_at: 1.hour.from_now)
    borrowed = make_clone_job(volume: volumes(:user_nginx_web),
      state: VolumeCloneJob::STATE_COMPLETED, owns_snapshot: false,
      archive_name: archive_name("someone-elses"), next_cleanup_at: 1.minute.ago)

    sweep!

    assert_equal [ready.id], trash_ids
    assert_not_includes trash_ids, backing_off.id
    assert_not_includes trash_ids, borrowed.id, "a snapshot we did not create is never ours to delete"
  end

  test "does not re-enqueue cleanup for a row whose snapshot was already trashed" do
    done = make_clone_job(volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_COMPLETED, owns_snapshot: true,
      archive_name: archive_name("gone"), snapshot_trashed_at: 5.minutes.ago,
      next_cleanup_at: 1.minute.ago)

    sweep!

    assert_empty trash_ids
    assert_not_nil done.reload.snapshot_trashed_at
  end

  test "does not enqueue cleanup for a row that is still working" do
    make_clone_job(volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: true,
      archive_name: archive_name("inflight"), next_cleanup_at: 1.minute.ago,
      state_deadline_at: 4.hours.from_now)

    sweep!

    assert_empty trash_ids
  end

  # --- resilience -------------------------------------------------------------------

  # The whole reason deadline enforcement lives in the sweeper is that these rows are the ones
  # with a broken object graph. So the terminal funnel is stubbed to blow up for ONE row, and
  # the last-resort UPDATE is made to blow up too (its SystemEvent write fails), which is the
  # only way to reach the per-row rescue in force_terminate_overdue!. Everything else in the
  # sweep must still happen.
  test "one poisoned row does not stop the sweep" do
    poison = make_clone_job(volume: volumes(:wordpress_web),
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, state_deadline_at: 1.minute.ago,
      owns_snapshot: true, archive_name: archive_name("poison"), next_poll_at: 1.minute.ago)
    healthy_overdue = make_clone_job(volume: volumes(:nginx_web),
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, state_deadline_at: 1.minute.ago,
      next_poll_at: 1.minute.ago)
    due = make_clone_job(volume: volumes(:user_nginx_web), next_poll_at: 1.minute.ago)

    real_new = VolumeServices::CloneStepService.method(:new)
    real_create = SystemEvent.method(:create!)

    service_stub = lambda do |job|
      raise "poisoned tick" if job.id == poison.id
      real_new.call(job)
    end
    # force_fail!'s durable record. Raising here escapes terminate!'s own rescue.
    system_event_stub = lambda do |*args, **kwargs|
      attrs = args.first.is_a?(Hash) ? args.first.merge(kwargs) : kwargs
      raise ActiveRecord::StatementInvalid, "poisoned row" if attrs[:message].to_s.include?("force-terminated")
      real_create.call(attrs)
    end

    VolumeServices::CloneStepService.stub(:new, service_stub) do
      SystemEvent.stub(:create!, system_event_stub) do
        sweep!
      end
    end

    assert_equal VolumeCloneJob::STATE_FAILED, healthy_overdue.reload.state,
      "the row after the poisoned one must still be force-terminated"
    assert_equal [due.id], step_ids,
      "due ticks must still be dispatched after a poisoned row"
    # The last-resort UPDATE lands before the SystemEvent write that blows up, so even the
    # poisoned row is closed out and its archive is queued for reaping.
    poison.reload
    assert_equal VolumeCloneJob::STATE_FAILED, poison.state
    assert_not_nil poison.next_cleanup_at
  end

  test "an empty database is a no-op" do
    VolumeCloneJob.delete_all
    assert_nothing_raised { sweep! }
    assert_empty step_ids
    assert_empty trash_ids
  end
end
