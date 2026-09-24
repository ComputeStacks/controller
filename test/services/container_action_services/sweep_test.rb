require "test_helper"

class ContainerActionServices::SweepTest < ActiveSupport::TestCase
  setup do
    ContainerActionWorkers::DispatchWorker.clear
    @project = deployments(:project_test)
  end

  def cap(**attrs)
    ContainerActionRequest.create!({action_id: SecureRandom.uuid, action_type: "test_action",
      project_id: @project.id.to_s, status: "received", params: {}, changelog_seq: 1}.merge(attrs))
  end

  test "reaps stuck dispatching rows into the retry path" do
    r = cap(status: "dispatching")
    r.update_column(:updated_at, 10.minutes.ago)
    ContainerActionServices::Sweep.new.call
    assert r.reload.failed?
  end

  test "collapses exact-duplicate pending actions; anything different dispatches on its own" do
    dup1 = cap(params: {"foo" => "bar"}, changelog_seq: 1)
    dup2 = cap(params: {"foo" => "bar"}, changelog_seq: 2)
    other = cap(params: {"foo" => "baz"}, changelog_seq: 3)
    ContainerActionServices::Sweep.new.call
    assert dup1.reload.superseded?, "older duplicate collapsed"
    refute dup2.reload.superseded?, "newest duplicate survives"
    refute other.reload.superseded?, "differing params dispatch independently"
  end

  test "per-project dispatch budget caps enqueues per sweep" do
    budget = ContainerActionServices::Sweep::PER_PROJECT_BUDGET
    (budget + 3).times { |i| cap(params: {"n" => i}) } # distinct params so they aren't coalesced
    ContainerActionServices::Sweep.new.call
    assert_equal budget, ContainerActionWorkers::DispatchWorker.jobs.size
  end

  test "runs cleanly with nothing actionable" do
    assert_nothing_raised { ContainerActionServices::Sweep.new.call }
  end
end
