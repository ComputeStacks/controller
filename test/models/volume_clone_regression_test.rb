require "test_helper"

##
# Regression suite for the production volume-clone incident.
#
# Every test here fails by construction against the pre-rewrite code. They are grouped in one
# file on purpose: these five behaviours are the incident, and each one is cheap to break again
# from a different file.
class VolumeCloneRegressionTest < ActiveSupport::TestCase
  include CloneTestHelpers

  setup do
    @source = volumes(:mysql)
    @target = volumes(:wordpress_web)
    @node = nodes(:testone)
  end

  # === 1. Root cause: the memoized repo_info ========================================
  #
  # The old CloneVolumeService warmed `repo_info` before requesting the backup and then polled
  # the frozen copy for 300 seconds, so the archive it was waiting for could never appear —
  # the clone timed out on every volume that needed a fresh snapshot.

  test "a projected archive is invisible until the repo_info memo is dropped" do
    seed_archives(@source, [auto_archive_name(at: 2.days.ago)])

    # Something reads the repo first — in production, deciding whether a recent snapshot could
    # be reused. That warms the memo.
    assert_equal 1, @source.list_archives.count
    assert_nil @source.find_archive_by_label("clone-1")

    landed = archive_name("clone-1")
    append_archive(@source, landed)

    assert_nil @source.find_archive_by_label("clone-1"),
      "stale memo: this is exactly what made the old clone poll a frozen archive list"
    assert_equal 1, @source.list_archives.count

    assert_equal landed, @source.reset_repo_info!.find_archive_by_label("clone-1")
    assert_equal 2, @source.list_archives.count
  end

  test "reset_repo_info! is chainable and returns the volume" do
    seed_archives(@source, [])
    assert_equal @source, @source.reset_repo_info!
  end

  test "a fresh object always observes the projected archives" do
    landed = archive_name("clone-2")
    seed_archives(@source, [landed])
    assert_equal landed, Volume.find(@source.id).find_archive_by_label("clone-2")
  end

  # === 2. latest_archive must be nil-safe ===========================================
  #
  # `list_archives` omits `:created` for any name it cannot date, so the old
  # `sort_by { |i| i[:created] }` raised "comparison of NilClass with Time failed" as soon as
  # ONE manually-created archive existed in the repo — killing the clone before it started.

  test "latest_archive survives archives it cannot date and returns the newest good one" do
    good_old = archive_name("clone-old", at: 3.days.ago)
    good_new = archive_name("clone-new", at: 1.hour.ago)
    seed_archives(@source, [
      unparseable_archive_name("manual-2020-01-01"),
      good_old,
      bad_timestamp_archive_name("clone-broken"),
      good_new
    ])
    @source.reset_repo_info!

    # Proof the fixture really does contain the poison the old implementation choked on.
    assert_raises(ArgumentError) { @source.list_archives.sort_by { |i| i[:created] } }

    newest = nil
    assert_nothing_raised { newest = @source.latest_archive }
    assert_not_nil newest
    assert_equal good_new, Base64.urlsafe_decode64(newest[:id])
  end

  test "latest_archive is nil when nothing in the repo can be dated" do
    seed_archives(@source, [unparseable_archive_name("manual-2020-01-01"),
      bad_timestamp_archive_name("clone-broken")])
    @source.reset_repo_info!

    assert_nothing_raised { assert_nil @source.latest_archive }
  end

  test "latest_archive is nil on an empty repo" do
    seed_archives(@source, [])
    assert_nil @source.reset_repo_info!.latest_archive
  end

  # === 3. Parallel clones must not correlate through a shared audit =================
  #
  # The old code polled `audit.event_logs.find_by(locale:)` on the audit shared by every volume
  # in the order, so the second volume matched the FIRST volume's completed event and "finished"
  # without ever having been restored. Correlation is now by the AgentTask id on the row.

  test "completing one clone's backup task does not advance a parallel clone" do
    # Deliberately ONE audit for both jobs — the shared-audit topology that broke the old code.
    shared_audit = make_clone_audit(@target)

    task_a = make_agent_task(status: "completed", volume: @source)
    task_b = make_agent_task(status: "running", volume: volumes(:wordpress_webconfig))

    job_a = make_clone_job(volume: @target, source_volume: @source, audit: shared_audit,
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, clone_label: "lbl-a",
      backup_task_id: task_a.id, backup_dispatched_at: 5.minutes.ago)
    job_b = make_clone_job(volume: volumes(:nginx_web), source_volume: volumes(:wordpress_webconfig),
      audit: shared_audit, state: VolumeCloneJob::STATE_AWAITING_BACKUP, clone_label: "lbl-b",
      backup_task_id: task_b.id, backup_dispatched_at: 5.minutes.ago)

    assert_equal shared_audit.id, job_a.audit_id
    assert_equal shared_audit.id, job_b.audit_id
    assert_equal 2, shared_audit.event_logs.count, "two umbrella events on one audit"

    with_fake_agent do
      VolumeWorkers::CloneStepWorker.new.perform(job_a.id)
      VolumeWorkers::CloneStepWorker.new.perform(job_b.id)
    end

    assert_equal VolumeCloneJob::STATE_DISCOVERING_ARCHIVE, job_a.reload.state
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job_b.reload.state,
      "B's backup is still running; A completing must not move it"
    assert_nil job_b.archive_name

    # And when A's archive lands, only A picks it up.
    landed = archive_name("lbl-a")
    seed_archives(@source, [landed])

    with_fake_agent do
      VolumeWorkers::CloneStepWorker.new.perform(job_a.id)
      VolumeWorkers::CloneStepWorker.new.perform(job_b.id)
    end

    assert_equal landed, job_a.reload.archive_name
    assert job_a.owns_snapshot
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job_b.reload.state
    assert_nil job_b.archive_name
  end

  # === 4. Audit#raw_data is not a scratchpad ========================================
  #
  # dispatch_task! used to write the task id into the serialized `raw_data` column, which
  # Audit#formatted_name renders — so every backup's audit line read
  # "Me updated ---\n:task_id: ...".

  test "create_backup! leaves the audit's raw_data alone and the audit line renders normally" do
    audit = Audit.create!(event: "updated", rel_id: @source.id, rel_model: "Volume",
      user: users(:admin))
    @source.current_audit = audit

    jid = with_fake_agent { @source.create_backup!("clone-abc") }
    assert jid, "the dispatch itself must still work"

    audit.reload
    assert_nil audit.raw_data
    rendered = nil
    assert_nothing_raised { rendered = Array(audit.formatted_name).join(" ") }
    assert_includes rendered, "volume"
    assert_includes rendered, @source.name
    assert_not_includes rendered, "task_id"
    assert_not_includes rendered, "---"
  end

  test "restore_backup! and delete_backup! leave raw_data alone too" do
    audit = Audit.create!(event: "restored", rel_id: @target.id, rel_model: "Volume")
    @target.current_audit = audit
    @source.current_audit = audit

    with_fake_agent do
      assert @target.restore_backup!(archive_name("clone-abc"), @source.name)
      assert @source.delete_backup!(archive_name("clone-abc"))
    end

    assert_nil audit.reload.raw_data
  end

  # === 5. The reaper may kill the event; it may never kill the clone ================
  #
  # The umbrella event is presentational — the volume_clone_jobs row is authoritative. A tick
  # touches the event every pass (gated ticks included), which is what keeps StaleEventWorker
  # (1h) and EventLog.clean_event_status! (2h) off a legitimately long clone.

  test "a ticked clone event survives the reapers and an untouched one does not" do
    ticked = make_clone_job(volume: @target, source_volume: @source,
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, entered_state_at: 5.minutes.ago,
      state_deadline_at: 11.hours.from_now)
    abandoned = make_clone_job(volume: volumes(:nginx_web), source_volume: @source,
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, entered_state_at: 5.minutes.ago,
      state_deadline_at: 11.hours.from_now)

    [ticked, abandoned].each do |job|
      job.event_log.update_columns(status: "running", updated_at: 3.hours.ago)
    end

    # One tick of the live clone. No agent traffic: it is waiting on a task row that has not
    # been projected yet, so it just holds.
    with_fake_agent { VolumeWorkers::CloneStepWorker.new.perform(ticked.id) }
    assert ticked.event_log.reload.updated_at > 1.minute.ago, "a tick must touch the event"

    EventWorkers::StaleEventWorker.new.perform
    EventLog.clean_event_status!

    assert_equal "running", ticked.event_log.reload.status,
      "a clone that is ticking must not be reaped out from under itself"
    assert_not_equal "running", abandoned.event_log.reload.status

    # Either way the row — the authoritative state — survives untouched.
    [ticked, abandoned].each do |job|
      assert VolumeCloneJob.exists?(job.id)
      assert job.reload.working?, "the reaper drives events, never clone jobs"
    end
  end

  test "a clone job outlives the destruction of its umbrella event" do
    job = make_clone_job(volume: @target, source_volume: @source,
      state: VolumeCloneJob::STATE_AWAITING_BACKUP, state_deadline_at: 11.hours.from_now)
    event_id = job.event_log_id

    job.event_log.destroy!

    assert VolumeCloneJob.exists?(job.id)
    job.reload
    assert_equal event_id, job.event_log_id
    assert_nil job.event_log
    assert_nothing_raised do
      with_fake_agent { VolumeWorkers::CloneStepWorker.new.perform(job.id) }
    end
    assert job.reload.working?
  end
end
