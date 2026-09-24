require "test_helper"

class ContainerActionRequestTest < ActiveSupport::TestCase
  def build_req(status: "received", **attrs)
    ContainerActionRequest.create!(
      {action_id: SecureRandom.uuid, action_type: "test_action", project_id: "1",
       status: status, params: {"foo" => "bar"}, changelog_seq: 1}.merge(attrs)
    )
  end

  test "dispatch! atomically claims a received row exactly once" do
    req = build_req
    a = ContainerActionRequest.find(req.id)
    b = ContainerActionRequest.find(req.id) # both see status 'received'
    assert_equal true, a.dispatch!
    assert_equal false, b.dispatch! # loser: 0 rows matched the WHERE
    assert a.dispatching?
  end

  test "dispatch! claims a failed row whose backoff has elapsed" do
    assert_equal true, build_req(status: "failed", next_attempt_at: 1.minute.ago).dispatch!
  end

  test "dispatch! refuses a failed row whose backoff has NOT elapsed" do
    assert_equal false, build_req(status: "failed", next_attempt_at: 1.hour.from_now).dispatch!
  end

  test "dispatch! refuses a terminal row" do
    assert_equal false, build_req(status: "done").dispatch!
  end

  test "complete! only from dispatching and stores the result" do
    req = build_req
    assert_equal false, req.complete!({"x" => 1}) # not dispatching yet
    req.dispatch!
    assert req.complete!({"http_status" => 200})
    assert req.done?
    assert_equal 200, req.reload.result["http_status"]
  end

  test "retry_later! backs off, then gives up as dead after MAX_ATTEMPTS" do
    req = build_req
    max = ContainerActionRequests::StateManager::MAX_ATTEMPTS
    (max - 1).times do |i|
      assert req.dispatch! # claimable (backoff elapsed / fresh)
      assert req.retry_later!("boom")
      assert req.failed?
      assert_equal i + 1, req.attempts
      assert req.next_attempt_at > Time.current
      req.update_column(:next_attempt_at, 1.minute.ago) # simulate the backoff elapsing
    end
    assert req.dispatch!
    req.retry_later!("boom") # attempt == max -> dead
    assert req.dead?
  end

  test "actionable scope selects fresh + backoff-elapsed rows only" do
    recv = build_req
    disp = build_req(status: "dispatching")
    future = build_req(status: "failed", next_attempt_at: 1.hour.from_now)
    past = build_req(status: "failed", next_attempt_at: 1.minute.ago)
    done = build_req(status: "done")
    ids = ContainerActionRequest.actionable.pluck(:id)
    assert_includes ids, recv.id
    assert_includes ids, past.id
    refute_includes ids, disp.id
    refute_includes ids, future.id
    refute_includes ids, done.id
  end

  test "stuck? only for stale dispatching rows" do
    req = build_req
    req.dispatch!
    refute req.stuck?
    req.update_column(:updated_at, 10.minutes.ago)
    assert req.reload.stuck?
  end

  test "supersede! only from an active state" do
    assert build_req.supersede!(by: "winner")
    refute build_req(status: "done").supersede!(by: "winner")
  end
end
