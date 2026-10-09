require "test_helper"
require "minitest/mock"

##
# A power action on a node in maintenance is parked (event left pending, labeled with the
# node) and run by ContainerWorkers::DeferredPowerWorker when maintenance ends.
class PowerCycleDeferralTest < ActiveSupport::TestCase
  setup do
    @container = deployment_containers(:pma_1)
    @node = @container.node
    @node.update_columns(maintenance_requested: true, disconnected: false)
    @node.reload
    @audit = Audit.create_from_object!(@container, "updated", "127.0.0.1", users(:admin))
  end

  def deferred_events
    EventLog.where(status: "pending").where("labels ->> 'deferred_node_id' = ?", @node.id.to_s)
  end

  test "a restart on a node in maintenance is parked, not canceled" do
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    assert service.perform
    event = service.event.reload
    assert_equal "pending", event.status
    assert_equal service.action, event.labels["deferred_action"]
    assert_equal @container.global_id.to_s, event.labels["deferred_container"]
    assert_match(/maintenance ends/, event.event_details.last.data)
  end

  test "a disconnected node not in maintenance still cancels" do
    @node.update_columns(maintenance_requested: false, disconnected: true)
    @node.reload
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    refute service.perform
    assert_equal "cancelled", service.event.reload.status
  end

  test "a node rebooting during maintenance (disconnected) still parks" do
    @node.update_columns(disconnected: true)
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    assert service.perform
    assert_equal "pending", service.event.reload.status
  end

  test "a later request supersedes a parked one for the same container" do
    first = PowerCycleContainerService.new(@container, "stop", @audit)
    first.perform
    later_audit = Audit.create_from_object!(@container, "updated", "127.0.0.1", users(:admin))
    second = PowerCycleContainerService.new(@container, "start", later_audit)
    assert second.perform
    assert_equal "cancelled", first.event.reload.status
    assert_equal [second.event.id], deferred_events.pluck(:id)
  end

  test "containers acting under one audit each park their own event" do
    other = @container.service.containers.where.not(id: @container.id).first || deployment_containers(:wordpress_1)
    other.update_columns(node_id: @node.id)
    a = PowerCycleContainerService.new(@container, "restart", @audit)
    a.perform
    b = PowerCycleContainerService.new(other, "restart", @audit)
    b.perform
    refute_equal a.event.id, b.event.id
    assert_equal [@container.global_id.to_s, other.global_id.to_s].sort,
      deferred_events.map { |e| e.labels["deferred_container"] }.sort
  end

  test "nothing resumes while the node is still disconnected" do
    PowerCycleContainerService.new(@container, "restart", @audit).perform
    @node.update_columns(maintenance_requested: false, disconnected: true)
    ContainerWorkers::DeferredPowerWorker.new.perform(@node.id)
    assert_equal 1, deferred_events.count
  end

  test "the stale-event reaper spares a parked event for a week" do
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    service.perform
    plain = EventLog.create!(locale: "container.restart", status: "pending", event_code: "d611b2bbf50bd48c")
    EventLog.where(id: [service.event.id, plain.id]).update_all(updated_at: 3.hours.ago)
    EventLog.clean_event_status!
    assert_equal "pending", service.event.reload.status
    assert_equal "cancelled", plain.reload.status
    EventLog.where(id: service.event.id).update_all(updated_at: 8.days.ago)
    EventLog.clean_event_status!
    assert_equal "cancelled", service.event.reload.status
  end

  test "the worker resumes a parked action once, on the same event" do
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    service.perform
    @node.update_columns(maintenance_requested: false)

    resumed = []
    fake_new = lambda do |container, action, _audit|
      Struct.new(:event) { define_method(:perform) { resumed << [container, action, event]; true } }.new
    end
    PowerCycleContainerService.stub(:new, fake_new) do
      ContainerWorkers::DeferredPowerWorker.new.perform(@node.id)
      ContainerWorkers::DeferredPowerWorker.new.perform(@node.id)
    end
    assert_equal 1, resumed.size
    assert_equal [@container, service.action, service.event], resumed.first
    assert_empty deferred_events
    assert_nil service.event.reload.labels["deferred_action"]
  end

  test "a parked action for a deleted container is canceled" do
    service = PowerCycleContainerService.new(@container, "stop", @audit)
    service.perform
    event = service.event
    event.update!(labels: event.labels.merge("deferred_container" => "gid://computestacks/Deployment::Container/0"))
    @node.update_columns(maintenance_requested: false)
    ContainerWorkers::DeferredPowerWorker.new.perform(@node.id)
    assert_equal "cancelled", event.reload.status
  end

  test "automatic recovery never replaces a parked request" do
    parked = PowerCycleContainerService.new(@container, "stop", @audit)
    parked.perform
    recovery = PowerCycleContainerService.new(@container, "start", Audit.create_from_object!(@container, "updated", nil, nil))
    recovery.supersede = false
    recovery.perform
    assert_equal "pending", parked.event.reload.status
    assert_equal "cancelled", recovery.event.reload.status
  end

  test "a parked request is not superseded by one that is refused anyway" do
    parked = PowerCycleContainerService.new(@container, "stop", @audit)
    parked.perform
    running = EventLog.create!(locale: "container.restart", status: "running", event_code: "d611b2bbf50bd48c")
    running.containers << @container
    later = PowerCycleContainerService.new(@container, "start", Audit.create_from_object!(@container, "updated", nil, users(:admin)))
    later.perform
    assert_equal "pending", parked.event.reload.status
    assert_equal "cancelled", later.event.reload.status
  end

  test "a stop never switches a paused subscription back on" do
    container = deployment_containers(:user_nginx_1)
    container.node.update_columns(maintenance_requested: false, disconnected: false)
    container.subscription.update_columns(active: false)
    audit = Audit.create_from_object!(container, "updated", "127.0.0.1", users(:admin))
    PowerCycleContainerService.new(container, "stop", audit).perform
    refute container.subscription.reload.active
  end
end
