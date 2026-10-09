require "test_helper"

##
# PowerCycleContainerService#outcome names what #perform did, for callers that answer
# differently per case (the API's deferred 202 / offline 409).
class PowerCycleOutcomeTest < ActiveSupport::TestCase
  setup do
    @container = deployment_containers(:pma_1)
    @node = @container.node
    @node.update_columns(maintenance_requested: false, maintenance_holds: {}, disconnected: false)
    @node.reload
    @audit = Audit.create_from_object!(@container, "updated", "127.0.0.1", users(:admin))
  end

  def perform(action = "restart", container: @container)
    service = PowerCycleContainerService.new(container, action, @audit)
    result = service.perform
    [result, service.outcome]
  end

  test "queued on an online node" do
    assert_equal [true, :queued], perform
  end

  test "deferred on a node in maintenance" do
    @node.update_columns(maintenance_requested: true)
    @node.reload # the generated `maintenance` column
    assert_equal [true, :deferred], perform
  end

  test "refused_offline on a disconnected node" do
    @node.update_columns(disconnected: true)
    assert_equal [false, :refused_offline], perform
  end

  test "refused_offline when the container has no node" do
    @container.update_columns(node_id: nil)
    assert_equal [false, :refused_offline], perform(container: Deployment::Container.find(@container.id))
  end

  test "in_progress when another action is running" do
    other = EventLog.create!(locale: "container.restart", event_code: "d611b2bbf50bd48c", status: "running")
    other.containers << @container
    assert_equal [true, :in_progress], perform
  end

  test "failed on an unknown action" do
    assert_equal [false, :failed], perform("explode")
  end

  test "a shared audit event an earlier container already canceled is not reused" do
    unplaced = deployment_containers(:wordpress_1)
    unplaced.update_columns(node_id: nil)
    assert_equal [false, :refused_offline], perform(container: Deployment::Container.find(unplaced.id))
    canceled = @audit.event_logs.first
    refute canceled.active?

    @node.update_columns(maintenance_requested: true)
    @node.reload
    service = PowerCycleContainerService.new(@container, "restart", @audit)
    assert service.perform
    assert_equal :deferred, service.outcome
    refute_equal canceled.id, service.event.id
    assert service.event.reload.pending?
  end
end
