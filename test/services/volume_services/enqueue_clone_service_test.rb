require "test_helper"

##
# VolumeServices::EnqueueCloneService turns an order's `volume_clones` list into durable
# VolumeCloneJob rows. Everything it does is microseconds — resolve, validate, insert, enqueue —
# and the two things it must NOT do are (a) talk to a node and (b) hang its EventLogs off the
# order's audit.
class VolumeServices::EnqueueCloneServiceTest < ActiveSupport::TestCase
  include CloneTestHelpers

  setup do
    VolumeWorkers::CloneStepWorker.clear
    @project = deployments(:project_test)
    @source = volumes(:mysql)
    @target = volumes(:wordpress_web)
    @other_target = volumes(:nginx_web)
    @order = make_clone_order
    # BuildOrderService#122 stamps the order onto its audit as rel_model "Order" + rel_uuid.
    @order_audit = Audit.create!(event: "created", rel_model: "Order", rel_uuid: @order.id,
      ip_addr: "10.9.9.9", user: users(:admin))
    @event = make_provision_event(@order_audit)
  end

  # The order's provision event (ProcessOrderWorker:8).
  def make_provision_event(audit)
    event = EventLog.new(locale: "order.provision", locale_keys: {}, status: "pending",
      audit: audit, event_code: "0a3af01a3384fa10")
    event.deployments << @project
    event.save!
    event
  end

  # `perform` is run exactly once (a second run would append its errors a second time); its
  # return value is kept in @perform_result for the tests that care.
  def enqueue(clones)
    service = VolumeServices::EnqueueCloneService.new(@project, @event, clones)
    @perform_result = service.perform
    service
  end

  def step_job_ids
    VolumeWorkers::CloneStepWorker.jobs.map { |j| j["args"].first }
  end

  # --- happy path ------------------------------------------------------------------

  test "creates one row per entry with the right source, project and order" do
    service = nil
    assert_difference "VolumeCloneJob.count", 2 do
      service = enqueue([
        {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil},
        {vol_id: @other_target.id, source_vol_id: @source.id, source_snap: nil}
      ])
    end

    assert @perform_result
    assert_empty service.errors
    assert_equal [@target.id, @other_target.id], service.jobs.map(&:volume_id), "jobs in input order"

    job = VolumeCloneJob.find_by(volume_id: @target.id)
    assert_equal @source.id, job.source_volume_id
    assert_equal @project.id, job.deployment_id
    assert_equal @order.id, job.order_id
    assert_equal VolumeCloneJob::STATE_PENDING, job.state
    assert_nil job.requested_archive
    assert_not job.owns_snapshot
    assert_not_nil job.next_poll_at
  end

  test "enqueues exactly one CloneStepWorker per row" do
    service = enqueue([
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil},
      {vol_id: @other_target.id, source_vol_id: @source.id, source_snap: nil}
    ])

    assert_equal service.jobs.map(&:id).sort, step_job_ids.sort
    assert_equal 2, VolumeWorkers::CloneStepWorker.jobs.size
  end

  test "creates no EventLog of its own — the umbrella event is the step service's job" do
    assert_no_difference "EventLog.count" do
      enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    end
  end

  # --- invariant 2 (the production incident) ---------------------------------------

  # PowerCycleContainerService:41 is
  #   self.event = audit.event_logs.first if audit && audit.event_logs.count == 1
  # so a second EventLog on the ORDER's audit flips every container build onto its own event,
  # changes when the order completes, and arms ProcessOrderService#fail_process! — which
  # detaches the project's private network.
  test "the clone gets its own Volume audit and leaves the order audit with exactly one event" do
    service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    job = service.jobs.first

    assert_not_nil job.audit
    assert_not_equal @order_audit.id, job.audit_id
    assert_equal "Volume", job.audit.rel_model
    assert_equal @target.id, job.audit.rel_id
    assert_equal "restored", job.audit.event
    assert_equal users(:admin), job.audit.user
    assert_equal "10.9.9.9", job.audit.ip_addr.to_s

    assert_equal 1, @order_audit.reload.event_logs.count,
      "an extra EventLog on the order audit arms fail_process! (invariant 2)"
    assert_equal @event.id, @order_audit.event_logs.first.id
  end

  test "each volume in one order gets its own audit" do
    service = enqueue([
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil},
      {vol_id: @other_target.id, source_vol_id: @source.id, source_snap: nil}
    ])

    audit_ids = service.jobs.map(&:audit_id)
    assert_equal 2, audit_ids.uniq.size
    assert_equal 1, @order_audit.reload.event_logs.count
  end

  # --- structural failures ---------------------------------------------------------

  test "a missing target volume is an error and creates no row" do
    service = nil
    assert_no_difference "VolumeCloneJob.count" do
      service = enqueue([{vol_id: 999_999_999, source_vol_id: @source.id, source_snap: nil}])
    end

    assert_not @perform_result, "a structural error must fail the enqueue"
    assert_equal 1, service.errors.count
    assert_match(/999999999 not found/, service.errors.first)
    assert_empty service.jobs
    assert_empty VolumeWorkers::CloneStepWorker.jobs
  end

  test "a missing source volume is an error and creates no row" do
    # ContainerServiceProvisioner passes `source_vol_id: existing_volume&.id`, so nil is the
    # real-world shape of "the source the customer picked is gone".
    service = nil
    assert_no_difference "VolumeCloneJob.count" do
      service = enqueue([{vol_id: @target.id, source_vol_id: nil, source_snap: nil}])
    end

    assert_equal 1, service.errors.count
    assert_match(/Source volume nil not found/, service.errors.first)
    assert_match(/#{@target.label}/, service.errors.first)
    assert_empty VolumeWorkers::CloneStepWorker.jobs
  end

  test "a source volume in another region is an error and creates no row" do
    other_region = Region.create!(location: locations(:testlocation), name: "clone-test-az2")
    @source.update_columns(region_id: other_region.id)

    service = nil
    assert_no_difference "VolumeCloneJob.count" do
      service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    end

    assert_equal 1, service.errors.count
    assert_match(/different availability zone/, service.errors.first)
    assert_empty VolumeWorkers::CloneStepWorker.jobs
  end

  # --- source_snap ------------------------------------------------------------------

  test "an undecodable source_snap is an error, not an exception" do
    service = nil
    assert_nothing_raised do
      assert_no_difference "VolumeCloneJob.count" do
        service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: "!!!!"}])
      end
    end

    assert_equal 1, service.errors.count
    assert_match(/not valid/, service.errors.first)
    assert_empty VolumeWorkers::CloneStepWorker.jobs
  end

  test "a valid source_snap is stored as the RAW archive name" do
    raw = archive_name("clone-supplied")
    service = enqueue([
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: Base64.urlsafe_encode64(raw)}
    ])

    assert_empty service.errors
    assert_equal raw, service.jobs.first.requested_archive
    assert_not_equal Base64.urlsafe_encode64(raw), service.jobs.first.requested_archive
  end

  test "a strict-Base64 source_snap (no urlsafe padding tricks) also decodes" do
    raw = archive_name("clone-strict")
    service = enqueue([
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: Base64.strict_encode64(raw)}
    ])

    assert_empty service.errors
    assert_equal raw, service.jobs.first.requested_archive
  end

  test "a blank source_snap leaves requested_archive nil" do
    service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: ""}])
    assert_nil service.jobs.first.requested_archive
  end

  # --- idempotency / order retry ----------------------------------------------------

  test "a second call over the same order creates no duplicate row" do
    first = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    VolumeWorkers::CloneStepWorker.clear

    second = nil
    assert_no_difference "VolumeCloneJob.count" do
      second = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    end

    assert_empty second.errors
    assert_equal first.jobs.first.id, second.jobs.first.id
    assert_equal [first.jobs.first.id], step_job_ids
  end

  test "an order retry re-arms a terminal row instead of silently skipping it" do
    stale = make_clone_job(
      volume: @target,
      source_volume: @source,
      state: VolumeCloneJob::STATE_FAILED,
      archive_name: archive_name("dead"),
      clone_label: "dead",
      owns_snapshot: true,
      backup_task_id: SecureRandom.uuid,
      backup_dispatched_at: 1.hour.ago,
      attempts: 9,
      dispatch_attempts: 3,
      consecutive_errors: 5,
      last_error: "borg blew up",
      finished_at: 30.minutes.ago
    )

    service = nil
    assert_no_difference "VolumeCloneJob.count" do
      service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])
    end

    assert_empty service.errors
    stale.reload
    assert_equal VolumeCloneJob::STATE_PENDING, stale.state
    assert_equal 0, stale.attempts
    assert_equal 0, stale.dispatch_attempts
    assert_equal 0, stale.consecutive_errors
    assert_nil stale.finished_at
    assert_nil stale.last_error
    assert_nil stale.archive_name
    assert_nil stale.clone_label
    assert_nil stale.backup_task_id
    assert_nil stale.backup_dispatched_at
    assert_nil stale.event_log_id
    assert_not stale.owns_snapshot
    assert_equal @order.id, stale.order_id
    assert_equal [stale.id], step_job_ids

    # The wipe above makes the previous attempt's archive unreachable to the reaper, which
    # selects on owns_snapshot. It must not vanish silently — this is a real archive in the
    # customer's borg repo and the SystemEvent is the only thing left that names it.
    orphan = SystemEvent.where(event_code: CLONE_EVENT_CODES[:abandoned_snapshot]).last
    refute_nil orphan, "re-arming must record the snapshot it orphans"
    assert_equal archive_name("dead"), orphan.data["archive"]

    # And the cleanup bookkeeping must be reset, or the NEW run's snapshot never gets
    # scheduled for deletion either (enter_terminal! skips it when snapshot_trashed_at is set).
    assert_nil stale.snapshot_trashed_at
    assert_equal 0, stale.cleanup_attempts
    assert_nil stale.next_cleanup_at
  end

  test "re-arming a row whose snapshot was already trashed resets the cleanup bookkeeping" do
    stale = make_clone_job(
      volume: @target,
      source_volume: @source,
      state: VolumeCloneJob::STATE_COMPLETED,
      archive_name: archive_name("done"),
      clone_label: "done",
      owns_snapshot: true,
      snapshot_trashed_at: 2.hours.ago,
      cleanup_attempts: 3,
      next_cleanup_at: 1.hour.ago,
      finished_at: 3.hours.ago
    )

    enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])

    stale.reload
    assert_nil stale.snapshot_trashed_at, "a stale trash stamp makes the new run's snapshot leak"
    assert_equal 0, stale.cleanup_attempts
    assert_nil stale.next_cleanup_at
    # Nothing was orphaned here — the old archive is already gone.
    assert_equal 0, SystemEvent.where(event_code: CLONE_EVENT_CODES[:abandoned_snapshot]).count
  end

  test "an order retry leaves a row that is still working strictly alone" do
    live = make_clone_job(
      volume: @target,
      source_volume: @source,
      state: VolumeCloneJob::STATE_AWAITING_BACKUP,
      clone_label: "inflight",
      backup_task_id: "task-inflight",
      attempts: 7
    )
    before = live.reload.attributes.slice("state", "clone_label", "backup_task_id", "attempts", "event_log_id")

    service = enqueue([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])

    assert_empty service.errors
    assert_equal before, live.reload.attributes.slice("state", "clone_label", "backup_task_id", "attempts", "event_log_id")
    assert_equal [live.id], step_job_ids
  end

  test "one bad entry does not stop the good ones" do
    service = nil
    assert_difference "VolumeCloneJob.count", 1 do
      service = enqueue([
        {vol_id: 999_999_999, source_vol_id: @source.id, source_snap: nil},
        {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}
      ])
    end

    assert_equal 1, service.errors.count
    assert_equal 1, service.jobs.count
    assert_equal @target.id, service.jobs.first.volume_id
  end
end
