require "test_helper"

##
# One tick of the async volume-clone state machine.
#
# Every test drives VolumeServices::CloneStepService against a real volume_clone_jobs row
# and a FakeAgentClient, with the two "outside world" stub points replaced on the service
# INSTANCE (they are private by design, so a singleton override is the seam):
#
#   * #container_built?(volume) — a live Docker read (Deployment::Container#built?)
#   * #project_node!(node)      — an on-demand Agent::ChangelogProjector pass
#
# `step_once!` calls the private #step so a single transition can be asserted in isolation
# (it returns :advanced / :wait). `tick!` runs the whole public #perform — the lock, the
# umbrella-event touch, cancellation, deadline enforcement and up to MAX_ADVANCES states —
# and is what the gate/deadline/budget regressions use.
class VolumeServices::CloneStepServiceTest < ActiveSupport::TestCase
  include CloneTestHelpers

  SVC = VolumeServices::CloneStepService

  StepResult = Struct.new(:service, :result, :fake)

  # --- harness -------------------------------------------------------------------------

  # @return [VolumeServices::CloneStepService] with the two outside-world calls stubbed.
  def stub_service(job, built: true, on_project: nil)
    svc = SVC.new(job)
    svc.define_singleton_method(:container_built?) { |_volume| built }
    svc.define_singleton_method(:project_node!) do |node|
      (@projected ||= []) << node
      on_project&.call(node)
      true
    end
    svc.define_singleton_method(:projected) { @projected ||= [] }
    svc
  end

  # Run the full public tick.
  def tick!(job, fake: nil, built: true, on_project: nil, expect: true)
    fake ||= FakeAgentClient.new
    svc = stub_service(job, built: built, on_project: on_project)
    ok = with_fake_agent(fake) { svc.perform }
    assert_equal expect, ok, "perform returned #{ok.inspect}; errors=#{svc.errors.inspect}"
    job.reload
    StepResult.new(svc, ok, fake)
  end

  # Run exactly ONE state transition, so a single edge can be asserted without the rest of
  # the machine running on top of it.
  def step_once!(job, fake: nil, built: true, on_project: nil)
    fake ||= FakeAgentClient.new
    svc = stub_service(job, built: built, on_project: on_project)
    res = with_fake_agent(fake) { svc.send(:step) }
    job.reload
    StepResult.new(svc, res, fake)
  end

  # A second clone job off the SAME source volume. volume_clone_jobs.volume_id is UNIQUE,
  # so a sibling always needs its own target.
  def make_sibling(state:, target: volumes(:nginx_web), **attrs)
    make_clone_job(volume: target, source_volume: volumes(:mysql), state: state, **attrs)
  end

  def gate_details(job)
    job.event_log.event_details.where(event_code: CLONE_EVENT_CODES[:gate_waiting])
  end

  setup do
    @source = volumes(:mysql)
    @target = volumes(:wordpress_web)
    @node = nodes(:testone)
  end

  # =====================================================================================
  # pending
  # =====================================================================================

  test "pending creates the umbrella event, starts it, and advances" do
    job = make_clone_job(state: VolumeCloneJob::STATE_PENDING, event_log: nil)
    assert_nil job.event_log_id

    # built: false parks the machine in awaiting_container so only the pending edge ran.
    tick!(job, built: false)

    event = job.event_log
    assert_not_nil event, "the umbrella event must be created on the pending tick"
    assert_equal event.id, job.event_log_id, "event_log_id must be persisted on the row"
    assert_equal CLONE_LOCALE, event.locale
    assert_equal CLONE_EVENT_CODES[:umbrella], event.event_code

    assert event.running?, "umbrella event must be start!ed immediately, was #{event.status}"
    assert_not event.pending?, "a pending event is reaped by EventLog.clean_event_status!"

    assert_includes event.volumes, @target
    assert_includes event.deployments, job.deployment
    assert_includes event.container_services, @target.owner

    assert_not_nil job.started_at
    assert_equal VolumeCloneJob::STATE_AWAITING_CONTAINER, job.state
  end

  test "pending re-uses the umbrella event when one already exists" do
    job = make_clone_job(state: VolumeCloneJob::STATE_PENDING)
    existing = job.event_log

    assert_no_difference -> { EventLog.count } do
      step_once!(job, built: false)
    end
    assert_equal existing.id, job.event_log_id
  end

  test "INVARIANT 1: the umbrella event carries no task_id label and no AgentTask event code" do
    job = make_clone_job(state: VolumeCloneJob::STATE_PENDING, event_log: nil)
    tick!(job, built: false)
    event = job.event_log

    # If either of these were false, Agent::TaskReconciler#correlated_event would adopt the
    # umbrella event as the backup task's own and drive it to `completed` the moment the
    # backup finished — silently truncating the clone at the halfway point.
    assert_equal({}, event.labels, "the umbrella event must carry NO labels at all")
    assert_nil event.labels["task_id"]
    assert_not_includes AgentTask::EVENT_CODE.values, event.event_code,
      "the umbrella code must never collide with a task event_code"
  end

  test "INVARIANT 1: TaskReconciler does not adopt the umbrella event for the clone's backup task" do
    job = make_clone_job(state: VolumeCloneJob::STATE_PENDING, event_log: nil)
    tick!(job, built: false)
    event = job.event_log

    # The worst case: the backup task shares the clone's audit (audit_id + event_code is the
    # reconciler's fallback correlation) and completes.
    make_agent_task(id: "adopt-check", name: "volume.backup", status: "completed",
      volume: @source, audit_id: job.audit_id)
    Agent::TaskReconciler.new.call

    assert event.reload.running?,
      "the umbrella event was driven to #{event.status} by the backup task — the clone would be truncated"
    assert_nil event.labels["task_id"]
  end

  # =====================================================================================
  # awaiting_container
  # =====================================================================================

  test "awaiting_container holds while the owning container is not built" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_CONTAINER)

    r = step_once!(job, built: false)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_CONTAINER, job.state
    assert_equal 1, job.attempts
    assert_operator job.next_poll_at, :>, Time.now
  end

  test "awaiting_container advances once the container is built" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_CONTAINER)

    r = step_once!(job, built: true)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_RESOLVING_SOURCE, job.state
  end

  # =====================================================================================
  # resolving_source — the four paths
  # =====================================================================================

  test "resolving_source (a) restores a caller-supplied archive and takes no backup" do
    requested = archive_name("user-backup", at: 3.days.ago)
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE, requested_archive: requested)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
    assert_equal requested, job.archive_name
    assert_equal false, job.owns_snapshot, "a caller-supplied archive is never ours to trash"
    assert_nil job.clone_label
    assert_empty r.fake.calls_of(:create_task), "no backup may be dispatched on a fast path"
  end

  test "resolving_source (b) adopts an in-flight sibling's archive of the same source" do
    adopted = archive_name("clone-sibling")
    sibling = make_sibling(state: VolumeCloneJob::STATE_AWAITING_RESTORE, archive_name: adopted)
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
    assert_equal sibling.archive_name, job.archive_name
    assert_equal false, job.owns_snapshot, "the sibling owns that snapshot, not us"
    assert_empty r.fake.calls_of(:create_task)
  end

  test "resolving_source (b) adopts from every ADOPTABLE_STATES sibling" do
    SVC::ADOPTABLE_STATES.each do |state|
      adopted = archive_name("clone-#{state}")
      sibling = make_sibling(state: state, archive_name: adopted)
      job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

      step_once!(job)

      assert_equal adopted, job.archive_name, "did not adopt from a sibling in #{state}"
      assert_equal false, job.owns_snapshot
    ensure
      job&.destroy
      sibling&.destroy
    end
  end

  test "resolving_source (b) never adopts from a terminal sibling" do
    # A completed sibling's snapshot is already queued for trashing; a failed one's archive
    # may be partial.
    make_sibling(state: VolumeCloneJob::STATE_COMPLETED, archive_name: archive_name("clone-done"))
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    step_once!(job)

    assert_nil job.archive_name
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
  end

  test "resolving_source (c) reuses an archive newer than RECENT_ARCHIVE_WINDOW" do
    recent = archive_name("snap", at: (SVC::RECENT_ARCHIVE_WINDOW / 2).ago)
    seed_archives(@source, [recent])
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
    assert_equal recent, job.archive_name, "the RAW borg name must be stored, never a Base64 id"
    assert_equal false, job.owns_snapshot, "a reused snapshot is a real user backup — never trash it"
    assert_empty r.fake.calls_of(:create_task)
  end

  test "resolving_source (c) ignores an archive older than RECENT_ARCHIVE_WINDOW" do
    stale = archive_name("snap", at: (SVC::RECENT_ARCHIVE_WINDOW * 2).ago)
    seed_archives(@source, [stale])
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    step_once!(job)

    assert_nil job.archive_name
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
  end

  test "resolving_source (c) survives an archive whose name cannot be dated" do
    # list_archives omits :created for these, which is what made a naive sort_by raise.
    seed_archives(@source, [unparseable_archive_name, bad_timestamp_archive_name])
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
  end

  test "resolving_source (d) mints a clone label and goes to dispatching_backup" do
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE, node: nil)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
    assert job.clone_label.present?, "a fresh backup needs a label to find its archive by"
    assert_equal false, job.owns_snapshot, "ownership is only claimed once the archive is named"
    assert_equal @node.id, job.node_id, "the borg repo is node-bound; the node must be pinned"
    assert_empty r.fake.calls_of(:create_task), "the POST belongs to dispatching_backup, not here"

    detail = job.event_log.event_details.where(event_code: CLONE_EVENT_CODES[:creating_snapshot]).last
    assert_not_nil detail
    assert_match(/Creating snapshot of source volume/, detail.data)
  end

  test "resolving_source holds when no online node currently holds the source" do
    take_node_offline!
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    r = step_once!(job)

    assert_equal :wait, r.result, "a node reboot must not fail a clone"
    assert_equal VolumeCloneJob::STATE_RESOLVING_SOURCE, job.state
    assert_equal 1, job.attempts
  end

  test "resolving_source fails when the source volume is in another region" do
    @source.update_columns(region_id: @target.region_id + 9999)
    job = make_clone_job(state: VolumeCloneJob::STATE_RESOLVING_SOURCE)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/not in this region/, job.last_error)
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:source_gone]).exists?
  end

  # =====================================================================================
  # dispatching_backup — the three re-entry cases
  # =====================================================================================

  test "dispatching_backup case 1: an already-stamped dispatch advances without a POST" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "clone-stamped", backup_task_id: "backup-1",
      backup_dispatched_at: 2.minutes.ago)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
    assert_empty r.fake.calls_of(:create_task), "a stamped dispatch must never re-POST"
  end

  test "dispatching_backup case 2: an existing AgentTask row is adopted, never re-POSTed" do
    # The POST landed and we crashed before stamping. The projected task row is the proof.
    make_agent_task(id: "backup-2", name: "volume.backup", status: "running", volume: @source)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "clone-crashed", backup_task_id: "backup-2",
      backup_dispatched_at: nil, entered_state_at: 1.second.ago)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
    assert_not_nil job.backup_dispatched_at, "the recovered dispatch must be stamped"
    assert_empty r.fake.calls_of(:create_task),
      "re-POSTing here would run a second borg backup — the no-double-borg guarantee"
  end

  test "dispatching_backup case 3: persists the id, creates the labelled child event, then POSTs" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-fresh")
    assert_nil job.backup_task_id

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
    assert_not_nil job.backup_task_id, "the id must be persisted BEFORE the POST"
    assert_not_nil job.backup_dispatched_at

    posted = r.fake.tasks_named("volume.backup")
    assert_equal 1, posted.size
    assert_equal job.backup_task_id, posted.first[:id],
      "the POSTed id must be the one persisted on the row, or a crash cannot be recovered"
    assert_equal "clone-fresh", posted.first[:archive]
    assert_equal @source.name, posted.first[:volume]

    child = EventLog.where("labels ->> 'task_id' = ?", job.backup_task_id).first
    assert_not_nil child, "the child event must exist"
    assert_equal AgentTask::EVENT_CODE["volume.backup"], child.event_code
    assert_equal job.backup_task_id, child.labels["task_id"]
    assert_equal child.created_at, child.updated_at,
      "the task_id label must be set AT CREATION, never stamped afterwards"
    assert_includes child.volumes, @source
    assert_not_equal job.event_log_id, child.id
  end

  test "dispatching_backup waits out the settle window when an id is already persisted" do
    # A persisted id with no task row: give the changelog a chance to reveal a POST that
    # landed just before the crash before sending another one.
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP,
      clone_label: "clone-settle", backup_task_id: "backup-settle",
      entered_state_at: 1.second.ago)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
    assert_empty r.fake.calls_of(:create_task)

    # Past DISPATCH_GRACE the same (stable) id is finally POSTed.
    travel (SVC::DISPATCH_GRACE + 1.minute) do
      r2 = step_once!(job)
      assert_equal :advanced, r2.result
      assert_equal 1, r2.fake.calls_of(:create_task).size
      assert_equal "backup-settle", r2.fake.tasks_named("volume.backup").first[:id]
    end
  end

  test "a refused dispatch stays put, counts the attempt, and re-uses the same task id" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-refused")
    fake = FakeAgentClient.new(create_task: false)

    r = step_once!(job, fake: fake)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state, "a refusal is not a state change"
    assert_equal 1, job.dispatch_attempts
    assert_nil job.backup_dispatched_at
    first_id = job.backup_task_id
    assert_not_nil first_id

    detail = job.event_log.event_details.where(event_code: CLONE_EVENT_CODES[:backup_failed]).last
    assert_not_nil detail, "the first refusal is surfaced on the umbrella event"

    travel (SVC::DISPATCH_GRACE + 1.minute) do
      r2 = step_once!(job, fake: fake)
      assert_equal :wait, r2.result
      assert_equal 2, job.dispatch_attempts
      assert_equal first_id, job.backup_task_id,
        "retrying must re-use the persisted id so a POST that landed cannot become a second task"
      assert_equal 1, EventLog.where("labels ->> 'task_id' = ?", first_id).count,
        "a retried dispatch re-uses the child event that matches the stable task id"
    end
  end

  # =====================================================================================
  # awaiting_backup
  # =====================================================================================

  test "awaiting_backup holds while the task row has not been projected yet" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-wait", backup_task_id: "missing-task",
      backup_dispatched_at: 1.minute.ago, entered_state_at: 1.minute.ago)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
    assert_equal 1, job.attempts
  end

  test "awaiting_backup fails when the task never appears within TASK_APPEARANCE_GRACE" do
    entered = (SVC::TASK_APPEARANCE_GRACE + 1.minute).ago
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-ghost", backup_task_id: "ghost-task",
      backup_dispatched_at: entered, entered_state_at: entered)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/never appeared in the node's changelog/, job.last_error)
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:backup_failed]).exists?
  end

  test "awaiting_backup advances to discovering_archive when the task completes" do
    make_agent_task(id: "done-task", name: "volume.backup", status: "completed", volume: @source)
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-done", backup_task_id: "done-task", backup_dispatched_at: 1.minute.ago)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_DISCOVERING_ARCHIVE, job.state
    detail = job.event_log.event_details.where(event_code: CLONE_EVENT_CODES[:creating_snapshot]).last
    assert_match(/Snapshot clone-done created/, detail.data)
  end

  test "awaiting_backup fails terminally and carries the task's error through" do
    make_agent_task(id: "bad-task", name: "volume.backup", status: "failed", volume: @source,
      result: {"error" => "boom"})
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-bad", backup_task_id: "bad-task", backup_dispatched_at: 1.minute.ago)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/boom/, job.last_error)
    assert_includes r.service.errors.join(" "), "boom"
    assert job.event_log.reload.failed?
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:backup_failed]).exists?
  end

  # NB this pins the ABSOLUTE budget, not a stall extension. A running task does not buy more
  # time on a per-tick basis: what a 10GB backup gets is the flat 12h from entered_state_at.
  # The row here has a truncated deadline (reachable only via heal_state_stamps!, not via
  # enter_state!) so the re-assertion has something to repair.
  test "awaiting_backup restores its full budget when the deadline was truncated" do
    make_agent_task(id: "slow-task", name: "volume.backup", status: "running", volume: @source)
    entered = 1.hour.ago
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-slow", backup_task_id: "slow-task", backup_dispatched_at: 1.minute.ago,
      entered_state_at: entered, state_deadline_at: 10.minutes.from_now)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
    assert_in_delta entered + VolumeCloneJob::STATE_DEADLINES[VolumeCloneJob::STATE_AWAITING_BACKUP],
      job.state_deadline_at, 5.seconds,
      "the budget is entered_state_at + 12h, and nothing extends it beyond that"
  end

  test "a normal awaiting_backup tick does not push the deadline out" do
    make_agent_task(id: "slow-task2", name: "volume.backup", status: "running", volume: @source)
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "clone-slow2", backup_task_id: "slow-task2", backup_dispatched_at: 1.minute.ago,
      entered_state_at: 2.hours.ago)
    before = job.state_deadline_at

    step_once!(job)

    assert_in_delta before, job.state_deadline_at, 1.second,
      "the ceiling is fixed; a live task does not buy more of it"
  end

  # =====================================================================================
  # discovering_archive
  # =====================================================================================

  test "discovering_archive holds until the archive shows up, then records the raw name" do
    seed_archives(@source, [])
    job = make_clone_job(state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      clone_label: "clone-find", backup_task_id: "find-task", backup_dispatched_at: 1.minute.ago)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_DISCOVERING_ARCHIVE, job.state
    assert_equal [@node], r.service.projected, "a changelog pass must be forced on demand"
    assert_not_nil job.polled_at
    assert_nil job.archive_name

    raw = archive_name("clone-find")
    append_archive(@source, raw)

    travel (SVC::PROJECT_INTERVAL + 5.seconds) do
      r2 = step_once!(job)
      assert_equal :advanced, r2.result
    end

    assert_equal raw, job.archive_name, "store the RAW borg name; never round-trip through Base64"
    assert_equal true, job.owns_snapshot, "we created it, so we must trash it"
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
  end

  test "discovering_archive re-reads the repo after projecting, defeating the repo_info memo" do
    # The production bug: the old clone warmed repo_info before the backup and then polled a
    # frozen archive list for 300s. project_node! is the moment the new rows land.
    seed_archives(@source, [])
    raw = archive_name("clone-memo")
    job = make_clone_job(state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      clone_label: "clone-memo", backup_task_id: "memo-task", backup_dispatched_at: 1.minute.ago)

    landed = false
    r = step_once!(job, on_project: ->(_node) {
      append_archive(@source, raw)
      landed = true
    })

    assert landed
    assert_equal :advanced, r.result, "the archive that landed during this very pass must be seen"
    assert_equal raw, job.archive_name
  end

  test "discovering_archive that runs out of time fails and raises an operator SystemEvent" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISCOVERING_ARCHIVE,
      clone_label: "clone-lost", backup_task_id: "lost-task",
      backup_dispatched_at: 1.hour.ago, entered_state_at: 1.hour.ago,
      state_deadline_at: 5.minutes.ago)

    tick!(job)

    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/Timed out in state 'discovering_archive'/, job.last_error)

    # A wedged changelog cursor looks exactly like "the archive hasn't been created yet" and
    # never self-resolves, so this failure needs an operator, not just a user-facing event.
    events = SystemEvent.where(event_code: CLONE_EVENT_CODES[:archive_never_appeared])
    operator = events.detect { |e| e.message.include?("never found its snapshot") }
    assert_not_nil operator, "expected an operator SystemEvent, got #{events.map(&:message).inspect}"
    assert_equal job.id, operator.data[:clone_job]
    assert_equal "clone-lost", operator.data[:clone_label]
    assert_equal job.backup_task_id, operator.data[:backup_task_id]

    # A backup was taken but never named — the archive is now unaddressable, so the leak is
    # surfaced separately.
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:abandoned_snapshot]).exists?
  end

  # =====================================================================================
  # dispatching_restore / awaiting_restore
  # =====================================================================================

  test "dispatching_restore POSTs the restore with the source volume name" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_RESTORE,
      archive_name: archive_name("clone-restore"), owns_snapshot: true)

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_equal VolumeCloneJob::STATE_AWAITING_RESTORE, job.state
    posted = r.fake.tasks_named("volume.restore")
    assert_equal 1, posted.size
    assert_equal job.restore_task_id, posted.first[:id]
    assert_equal job.archive_name, posted.first[:archive]
    assert_equal @target.name, posted.first[:volume]
    assert_equal @source.name, posted.first[:params][:source_volume]
  end

  test "awaiting_restore completing drives the clone to completed through the terminal funnel" do
    make_agent_task(id: "restore-ok", name: "volume.restore", status: "completed", volume: @target)
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE,
      archive_name: archive_name("clone-final"), owns_snapshot: true,
      restore_task_id: "restore-ok", restore_dispatched_at: 1.minute.ago)

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_COMPLETED, job.state
    assert job.event_log.reload.success?, "the umbrella event must land on completed"
    assert_not_nil job.finished_at
    assert_nil job.last_error
    assert_in_delta 2.hours.from_now, job.next_cleanup_at, 5
  end

  test "awaiting_restore failing is terminal and carries the task's error" do
    make_agent_task(id: "restore-bad", name: "volume.restore", status: "failed", volume: @target,
      result: {"error" => "restore exploded"})
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE,
      archive_name: archive_name("clone-final"), owns_snapshot: true,
      restore_task_id: "restore-bad", restore_dispatched_at: 1.minute.ago)

    step_once!(job)

    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/restore exploded/, job.last_error)
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:restore_failed]).exists?
  end

  # cs-agent reports a hook/rollback failure as a SOFT failure: it synthesizes the generic
  # literal "task reported failure" into `error` and puts the actual diagnostic — the shell
  # command's own stderr — in `output`. Reading `error` first turned every one of those into
  # a placeholder on the customer's event, with the cause reachable only by reading the
  # node's log. Matches Agent::TaskReconciler#failure_reason, which already prefers `output`.
  test "awaiting_restore surfaces the agent's output over the generic error sentinel" do
    output = "postRestoreMysql cleanup returned a non-zero exit code\n" \
      "/mnt/data/backups holds no xtrabackup_checkpoints, so it is not a prepared mysql dump\n" \
      "postRestore failed, executing rollback."
    make_agent_task(id: "restore-soft", name: "volume.restore", status: "failed", volume: @target,
      result: {"error" => "task reported failure", "output" => output})
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE,
      archive_name: archive_name("clone-final"), owns_snapshot: true,
      restore_task_id: "restore-soft", restore_dispatched_at: 1.minute.ago)

    step_once!(job)

    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/holds no xtrabackup_checkpoints/, job.last_error)
    detail = job.event_log.event_details.where(event_code: CLONE_EVENT_CODES[:restore_failed]).last
    assert_match(/holds no xtrabackup_checkpoints/, detail.data,
      "the customer-facing clone event must carry the real diagnostic, not the sentinel")
  end

  # =====================================================================================
  # gates
  # =====================================================================================

  test "the same-source claim gates a follower's dispatch" do
    VolumeCloneJob::SOURCE_CLAIM_STATES.each do |state|
      sibling = make_sibling(state: state)
      job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-follow")

      r = step_once!(job)

      assert_equal :wait, r.result, "a sibling in #{state} must gate the follower"
      assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
      assert job.gated?
      assert_match(/same source volume/, job.gate_reason)
      assert_empty r.fake.calls_of(:create_task)
      assert_equal 1, gate_details(job).count, "exactly one line per distinct gate reason"
    ensure
      job&.destroy
      sibling&.destroy
    end
  end

  test "a sibling that has released the source claim hands its archive to the follower" do
    sib_archive = archive_name("sib")
    make_sibling(state: VolumeCloneJob::STATE_AWAITING_RESTORE, archive_name: sib_archive)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-free")

    r = step_once!(job)

    assert_equal :advanced, r.result
    assert_not job.gated?
    # Adoption, not a second backup: one backup of a source serves every clone of it. The
    # follower is past resolving_source (where adoption is normally decided), so dispatching_*
    # re-offers it — otherwise two clones of one 10GB volume run two full borg backups.
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
    assert_equal sib_archive, job.archive_name
    assert_not job.owns_snapshot, "an adopted archive belongs to the sibling, not to us"
    assert_empty r.fake.calls_of(:create_task)
  end

  test "the per-node borg cap gates a dispatch and releases once it drops below the limit" do
    cap = SVC::MAX_CONCURRENT_BORG_PER_NODE
    tasks = Array.new(cap) do |i|
      make_agent_task(id: "cap-#{i}", name: (i.even? ? "volume.backup" : "volume.restore"),
        status: "running", volume: @source)
    end
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-capped")

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
    assert job.gated?
    assert_match(/concurrent backup\/restore limit \(#{cap}\)/, job.gate_reason)
    assert_empty r.fake.calls_of(:create_task)

    tasks.first.update!(status: "completed")

    travel 5.minutes do
      r2 = step_once!(job)
      assert_equal :advanced, r2.result, "the gate must open below the cap"
      assert_equal VolumeCloneJob::STATE_AWAITING_BACKUP, job.state
      assert_not job.gated?
      assert_equal 1, r2.fake.calls_of(:create_task).size
    end
  end

  test "the per-node cap ignores active tasks whose node has gone offline" do
    other = Node.create!(label: "test09", hostname: "test09", public_ip: "127.0.0.9",
      primary_ip: "127.0.0.9", region: regions(:regionone), active: true, disconnected: true)
    Array.new(SVC::MAX_CONCURRENT_BORG_PER_NODE + 2) do |i|
      make_agent_task(id: "stale-#{i}", name: "volume.backup", status: "running",
        volume: @source, node: other)
    end
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-stale")

    r = step_once!(job)

    assert_equal :advanced, r.result, "a dead node's stale rows must not hold the gate shut forever"
    assert_equal 1, r.fake.calls_of(:create_task).size
  end

  test "a gated tick still touches the umbrella event and never shrinks the deadline" do
    make_sibling(state: VolumeCloneJob::STATE_AWAITING_BACKUP)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-touch")
    touched_before = job.event_log.updated_at
    deadline_before = job.state_deadline_at

    travel 10.minutes do
      tick!(job)

      # StaleEventWorker fails `running` events after 1h and clean_event_status! cancels
      # anything untouched for 2h — a legitimately long gate must not trip either.
      assert_operator job.event_log.reload.updated_at, :>, touched_before
      assert_operator job.state_deadline_at, :>=, deadline_before,
        "gated time must not consume the state deadline"
      assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
      assert job.gated?
    end
  end

  test "a gate held past MAX_GATED_TIME fails the clone loudly" do
    make_sibling(state: VolumeCloneJob::STATE_AWAITING_BACKUP)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-wedged",
      gate_blocked_since: (SVC::MAX_GATED_TIME + 1.hour).ago,
      gate_reason: "another clone is snapshotting the same source volume")

    r = step_once!(job)

    assert_equal :wait, r.result
    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_match(/Gave up after waiting/, job.last_error)
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:gate_waiting]).exists?,
      "a permanently-closed gate must reach an operator, not park silently"
  end

  # =====================================================================================
  # gate / deadline composition — the headline regression
  # =====================================================================================

  test "REGRESSION: a follower gated longer than its own state deadline is never failed" do
    # The sibling's backup legitimately takes 45 minutes. dispatching_backup's budget is 30.
    # Before the gate/deadline split, the follower failed at minute 30 for doing exactly
    # what it was told to do: wait.
    budget = VolumeCloneJob::STATE_DEADLINES[VolumeCloneJob::STATE_DISPATCHING_BACKUP]
    assert_equal 30.minutes, budget

    sibling = make_sibling(state: VolumeCloneJob::STATE_AWAITING_BACKUP)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-patient")
    start = Time.now

    9.times do |i|
      minutes = (i + 1) * 5
      travel_to start + minutes.minutes
      tick!(job)
      assert job.working?,
        "the follower went #{job.state} after #{minutes} minutes gated (#{job.last_error})"
      assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state
      assert job.gated?
      assert_operator job.state_deadline_at, :>, Time.now
    end

    # 45 minutes gated — well past the 30 minute budget — and still alive.
    assert_equal (start + 45.minutes).to_i, Time.now.to_i
    assert_equal 1, gate_details(job).count, "one gate line, however many ticks were spent waiting"
    assert_not_nil sibling
  end

  test "a gated follower adopts the leader's archive as soon as the source claim is released" do
    sibling = make_sibling(state: VolumeCloneJob::STATE_AWAITING_BACKUP)
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-resume")
    start = Time.now

    # 40 minutes gated, swept every 5 minutes (production sweeps every 15s).
    8.times do |i|
      travel_to start + ((i + 1) * 5).minutes
      tick!(job)
    end
    assert job.gated?
    assert_equal VolumeCloneJob::STATE_DISPATCHING_BACKUP, job.state

    # The sibling finishes its snapshot and leaves SOURCE_CLAIM_STATES.
    leader_archive = archive_name("clone-sibling")
    sibling.update!(state: VolumeCloneJob::STATE_DISPATCHING_RESTORE, archive_name: leader_archive)

    travel_to start + 45.minutes
    r = tick!(job)

    assert_not job.gated?
    assert job.working?, "the follower must resume, not fail"
    # It adopts rather than taking a second backup of the same source. Without the re-offer in
    # dispatching_* it would run its own full borg backup under "clone-resume", since adoption
    # is normally only decided in resolving_source. One tick carries it through the adoption
    # and straight on into the restore dispatch (MAX_ADVANCES allows four states, and the
    # tick's single agent operation is spent on the restore rather than a redundant backup).
    assert_equal VolumeCloneJob::STATE_AWAITING_RESTORE, job.state
    assert_equal leader_archive, job.archive_name
    assert_not job.owns_snapshot
    assert_empty r.fake.tasks_named("volume.backup"), "no second backup of the same source"
    assert_equal 1, r.fake.tasks_named("volume.restore").size
    assert_equal leader_archive, r.fake.tasks_named("volume.restore").first[:archive]
  end

  # =====================================================================================
  # MAX_ADVANCES / one agent operation per tick
  # =====================================================================================

  test "one perform never makes two dispatches, however many states it crosses" do
    label = "clone-budget"
    seed_archives(@source, [])
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: label)

    # Worst case: the backup task is already complete and its archive already visible the
    # instant the POST lands, so every following state is immediately satisfied.
    fake = FakeAgentClient.new(create_task: ->(body) {
      make_agent_task(id: body[:id], name: body[:name], status: "completed", volume: @source)
      append_archive(@source, archive_name(label))
      body[:id]
    })

    r = tick!(job, fake: fake)

    assert_equal 1, fake.calls_of(:create_task).size,
      "a tick spends its single outbound agent operation once and only once"
    assert_equal VolumeCloneJob::STATE_DISPATCHING_RESTORE, job.state
    assert_operator r.service.advances, :<=, SVC::MAX_ADVANCES
    assert_operator job.next_poll_at, :<=, Time.now, "a deferred tick is re-swept immediately"

    # The next tick spends its own budget on the restore.
    fake2 = FakeAgentClient.new
    tick!(job, fake: fake2)
    assert_equal 1, fake2.calls_of(:create_task).size
    assert_equal 1, fake2.tasks_named("volume.restore").size
    assert_equal VolumeCloneJob::STATE_AWAITING_RESTORE, job.state
  end

  test "a perform stops after MAX_ADVANCES states" do
    job = make_clone_job(state: VolumeCloneJob::STATE_PENDING, event_log: nil,
      requested_archive: archive_name("user-supplied"))

    r = tick!(job)

    # pending -> awaiting_container -> resolving_source -> dispatching_restore -> awaiting_restore
    assert_equal SVC::MAX_ADVANCES, r.service.advances
    assert_equal VolumeCloneJob::STATE_AWAITING_RESTORE, job.state
    assert_equal 1, r.fake.calls_of(:create_task).size
  end

  # =====================================================================================
  # the terminal funnel
  # =====================================================================================

  test "enter_terminal! stamps finished_at and a 2 hour cleanup on success" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: true,
      archive_name: archive_name("clone-term"))
    svc = SVC.new(job)

    assert svc.enter_terminal!(VolumeCloneJob::STATE_COMPLETED)
    job.reload

    assert_equal VolumeCloneJob::STATE_COMPLETED, job.state
    assert_not_nil job.finished_at
    assert_nil job.last_error
    assert_in_delta 2.hours.from_now, job.next_cleanup_at, 5
    assert_empty svc.errors
    assert job.event_log.reload.success?
  end

  test "enter_terminal! records the reason and keeps a failed clone's snapshot for 24 hours" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: true,
      archive_name: archive_name("clone-term"))
    svc = SVC.new(job)

    assert svc.enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: "boom",
      event_code: CLONE_EVENT_CODES[:restore_failed])
    job.reload

    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_equal "boom", job.last_error
    assert_not_nil job.finished_at
    assert_in_delta 24.hours.from_now, job.next_cleanup_at, 5,
      "the snapshot is the only forensic artifact of a failed clone"
    assert_includes svc.errors, "boom"
    assert job.event_log.reload.failed?
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:restore_failed]).exists?
  end

  test "enter_terminal! schedules no cleanup when the snapshot is not ours" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: false,
      archive_name: archive_name("user-backup"))

    assert SVC.new(job).enter_terminal!(VolumeCloneJob::STATE_COMPLETED)

    assert_nil job.reload.next_cleanup_at, "a user's own backup must never be scheduled for trashing"
  end

  test "enter_terminal! schedules no cleanup for a snapshot that was already trashed" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: true,
      archive_name: archive_name("clone-gone"), snapshot_trashed_at: 1.minute.ago)

    assert SVC.new(job).enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: "late")

    assert_nil job.reload.next_cleanup_at
  end

  test "enter_terminal! leaves an already-terminal job exactly as it is" do
    job = make_clone_job(state: VolumeCloneJob::STATE_COMPLETED, owns_snapshot: false,
      finished_at: 1.hour.ago)
    finished = job.finished_at

    assert SVC.new(job).enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: "too late")
    job.reload

    assert_equal VolumeCloneJob::STATE_COMPLETED, job.state
    assert_nil job.last_error
    assert_equal finished.to_i, job.finished_at.to_i
  end

  test "enter_terminal! tolerates an umbrella event a reaper already terminated" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_BACKUP, owns_snapshot: true,
      clone_label: "clone-reaped", archive_name: archive_name("clone-reaped"))
    event = job.event_log
    event.start!
    event.cancel!("reaped by clean_event_status!")
    assert_equal "cancelled", event.reload.status
    assert_equal false, event.fail!("too late"),
      "a cancelled event refuses fail! — enter_terminal! must survive that"

    svc = SVC.new(job)
    assert svc.enter_terminal!(VolumeCloneJob::STATE_FAILED, reason: "boom",
      event_code: CLONE_EVENT_CODES[:backup_failed])
    job.reload

    assert_equal VolumeCloneJob::STATE_FAILED, job.state
    assert_equal "boom", job.last_error
    assert_in_delta 24.hours.from_now, job.next_cleanup_at, 5
    assert_equal "cancelled", event.reload.status
    assert SystemEvent.where(event_code: CLONE_EVENT_CODES[:backup_failed]).exists?,
      "the failure must be emitted whether or not the event was still drivable"
  end

  test "INVARIANT 2: enter_terminal! summarises on the order's provision event without joining its audit" do
    order = make_clone_order
    order_audit = Audit.create!(event: "order", rel_uuid: order.id, rel_model: "Order")
    provision = EventLog.create!(locale: "orders.provision", locale_keys: {}, status: "running",
      audit: order_audit, event_code: "0a3af01a3384fa10")
    assert_equal provision, order.provision_event

    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, order: order,
      archive_name: archive_name("clone-order"))

    assert SVC.new(job).enter_terminal!(VolumeCloneJob::STATE_COMPLETED)

    line = provision.event_details.where(event_code: CLONE_EVENT_CODES[:order_restoring_background]).last
    assert_not_nil line, "order forensics must stay usable even though clone events are on their own audit"
    assert_match(/Volume clone completed/, line.data)

    # Each clone carries its OWN audit. An extra EventLog on the order's audit flips
    # PowerCycleContainerService's `audit.event_logs.count == 1` topology check and arms
    # ProcessOrderService#fail_process!, which detaches the project's private network.
    assert_not_equal order_audit.id, job.audit_id
    assert_equal 1, order_audit.event_logs.count
    assert_equal "Volume", job.audit.rel_model
  end

  # =====================================================================================
  # cancellation
  # =====================================================================================

  test "a destroyed target volume cancels the clone on the next tick" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_RESTORE, owns_snapshot: true,
      archive_name: archive_name("clone-cancel"), restore_task_id: "cancel-task",
      restore_dispatched_at: 1.minute.ago)
    event = job.event_log

    # NB deleted directly: Volume#destroy currently blows up on a clone job (see the
    # dependent: :nullify / NOT NULL mismatch documented in volume_clone_jobs).
    Volume.where(id: job.volume_id).delete_all

    r = tick!(job.reload)

    assert_equal VolumeCloneJob::STATE_CANCELLED, job.state
    assert_match(/Target volume no longer exists/, job.last_error)
    assert_not_nil job.finished_at
    assert_in_delta 24.hours.from_now, job.next_cleanup_at, 5,
      "the snapshot we created still has to be trashed"
    assert_equal "cancelled", event.reload.status
    assert_empty r.fake.calls_of(:create_task)
  end

  test "a destroyed source volume cancels the clone" do
    job = make_clone_job(state: VolumeCloneJob::STATE_DISPATCHING_BACKUP, clone_label: "clone-src")
    Volume.where(id: job.source_volume_id).delete_all

    tick!(job.reload)

    assert_equal VolumeCloneJob::STATE_CANCELLED, job.state
    assert_match(/Source volume no longer exists/, job.last_error)
  end

  test "a trashed project cancels the clone" do
    job = make_clone_job(state: VolumeCloneJob::STATE_AWAITING_CONTAINER)
    job.deployment.mark_trashed!

    tick!(job)

    assert_equal VolumeCloneJob::STATE_CANCELLED, job.state
    assert_match(/Project has been trashed/, job.last_error)
  end

  test "a cancelled job stays cancelled and does nothing on a later tick" do
    job = make_clone_job(state: VolumeCloneJob::STATE_CANCELLED, finished_at: 1.hour.ago,
      last_error: "Target volume no longer exists.")

    r = tick!(job)

    assert_equal VolumeCloneJob::STATE_CANCELLED, job.state
    assert_empty r.fake.calls_of(:create_task)
    assert_equal 0, job.attempts
  end
end
