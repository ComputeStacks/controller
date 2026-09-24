require "test_helper"

class ContainerActionServices::DispatchTest < ActiveSupport::TestCase
  setup do
    @saved = ContainerActionRegistry.instance_variable_get(:@handlers).dup
    ContainerActionRegistry.register("test_action", "FakeActionHandler")
    FakeActionHandler.reset!
    @project = deployments(:project_test)
  end

  teardown do
    ContainerActionRegistry.instance_variable_set(:@handlers, @saved)
  end

  def req(status: "received", action_type: "test_action", project_id: @project.id.to_s, params: {"foo" => "bar"})
    ContainerActionRequest.create!(action_id: SecureRandom.uuid, action_type: action_type,
      project_id: project_id, status: status, params: params, changelog_seq: 1)
  end

  def dispatch(r) = ContainerActionServices::Dispatch.new(r).call

  test "accepted -> done" do
    FakeActionHandler.reset!(result: FakeActionHandler::Result.new(status: :accepted, http_status: 202))
    r = req
    dispatch(r)
    assert r.reload.done?
    assert_equal 202, r.result["http_status"]
    assert_equal 1, FakeActionHandler.calls
  end

  test "handler rejected -> dead + SystemEvent" do
    FakeActionHandler.reset!(result: FakeActionHandler::Result.new(status: :rejected, reason: "bad request"))
    r = req
    assert_difference -> { SystemEvent.count }, 1 do
      dispatch(r)
    end
    assert r.reload.dead?
  end

  test "transient failure -> failed with backoff" do
    FakeActionHandler.reset!(result: FakeActionHandler::Result.new(status: :failed, reason: "429"))
    r = req
    dispatch(r)
    assert r.reload.failed?
    assert_equal 1, r.attempts
    assert r.next_attempt_at > Time.current
  end

  test "no registered handler -> unhandled" do
    ContainerActionRegistry.instance_variable_set(:@handlers, {})
    r = req
    dispatch(r)
    assert r.reload.unhandled?
  end

  test "unknown project -> rejected, handler not called" do
    r = req(project_id: "99999999")
    dispatch(r)
    assert r.reload.rejected?
    assert_equal 0, FakeActionHandler.calls
  end

  test "engine does not own the project -> rejected, handler not called" do
    FakeActionHandler.reset!(owns: false)
    r = req
    dispatch(r)
    assert r.reload.rejected?
    assert_equal 0, FakeActionHandler.calls
  end

  test "concurrent dispatch runs the handler exactly once (atomic claim)" do
    r = req
    a = ContainerActionRequest.find(r.id)
    b = ContainerActionRequest.find(r.id) # both loaded as 'received'
    ContainerActionServices::Dispatch.new(a).call
    ContainerActionServices::Dispatch.new(b).call
    assert_equal 1, FakeActionHandler.calls
    assert a.reload.done?
  end
end
