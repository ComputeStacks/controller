require "test_helper"

##
# DeployProjectService is the order's provisioning fan-out. The clone-related contract is
# narrow: when `volume_clones` is set it must write durable VolumeCloneJob rows and return —
# never block on a backup/restore — and when it is empty (the other two callers,
# app/workers/deployment_workers/sftp_init_worker.rb:15 and
# app/services/node_services/evacuate_node_service.rb:116, never set it) nothing about it may
# change.
class DeployServices::DeployProjectServiceTest < ActiveSupport::TestCase
  include CloneTestHelpers

  setup do
    VolumeWorkers::CloneStepWorker.clear
    @project = deployments(:project_test)
    @source = volumes(:mysql)
    @target = volumes(:wordpress_web)
    @order = make_clone_order
    @audit = Audit.create!(event: "created", rel_model: "Order", rel_uuid: @order.id,
      ip_addr: "127.0.0.1", user: users(:admin))
    @event = EventLog.create!(locale: "order.provision", event_code: "0a3af01a3384fa10",
      audit: @audit, status: "pending")
  end

  def service(volume_clones = [])
    svc = DeployServices::DeployProjectService.new(@project, @event)
    svc.volume_clones = volume_clones
    svc
  end

  test "volume_clones defaults to empty" do
    assert_equal [], DeployServices::DeployProjectService.new(@project, @event).volume_clones
  end

  test "with volume_clones set it writes rows and hands them to the sweeper without dispatching" do
    svc = service([{vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}])

    with_fake_agent do |fake|
      assert_difference "VolumeCloneJob.count", 1 do
        assert svc.perform, svc.errors.inspect
      end
      # The old code ran the clone INLINE here: a Timeout+sleep loop of up to ~46 minutes per
      # volume inside ProcessOrderWorker. Nothing may go out to a node from this call.
      assert_empty fake.calls_of(:create_task),
        "the clone must be deferred, never dispatched inside the order"
    end

    assert_empty svc.errors
    job = VolumeCloneJob.find_by(volume_id: @target.id)
    assert_equal @source.id, job.source_volume_id
    assert_equal @project.id, job.deployment_id
    assert_equal @order.id, job.order_id
    assert_equal VolumeCloneJob::STATE_PENDING, job.state
    assert_equal [job.id], VolumeWorkers::CloneStepWorker.jobs.map { |j| j["args"].first }
  end

  test "the clone rows carry their own audits, leaving the order audit with one event" do
    svc = service([
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil},
      {vol_id: volumes(:nginx_web).id, source_vol_id: @source.id, source_snap: nil}
    ])

    with_fake_agent { assert svc.perform, svc.errors.inspect }

    audits = VolumeCloneJob.pluck(:audit_id)
    assert_equal 2, audits.compact.uniq.count
    assert_not_includes audits, @audit.id
    # PowerCycleContainerService:41 keys container-build topology off this being exactly 1.
    assert_equal 1, @audit.reload.event_logs.count
  end

  test "with no volume_clones it creates nothing and enqueues no clone work" do
    svc = service([])

    with_fake_agent do |fake|
      assert_no_difference "VolumeCloneJob.count" do
        assert svc.perform, svc.errors.inspect
      end
      assert_empty fake.calls_of(:create_task)
    end

    assert_empty svc.errors
    assert_empty VolumeWorkers::CloneStepWorker.jobs
  end

  # The bug this whole change exists to fix: the old line was `errors + cv.errors`, whose
  # result was discarded, so the ONE branch that reported "this volume was never cloned"
  # was thrown away and the order completed green over a missing restore.
  test "an enqueue error lands in errors and fails the deploy" do
    svc = service([{vol_id: @target.id, source_vol_id: nil, source_snap: nil}])

    result = nil
    with_fake_agent do
      assert_no_difference "VolumeCloneJob.count" do
        result = svc.perform
      end
    end

    assert_not result, "a clone that could not even be scheduled must fail the order"
    assert_equal 1, svc.errors.count
    assert_match(/Source volume nil not found/, svc.errors.first)
  end

  test "a bad entry fails the deploy while the good entries are still scheduled" do
    svc = service([
      {vol_id: 999_999_999, source_vol_id: @source.id, source_snap: nil},
      {vol_id: @target.id, source_vol_id: @source.id, source_snap: nil}
    ])

    result = nil
    with_fake_agent do
      assert_difference "VolumeCloneJob.count", 1 do
        result = svc.perform
      end
    end

    assert_not result
    assert_equal 1, svc.errors.count
    assert_equal @target.id, VolumeCloneJob.first.volume_id
  end
end
