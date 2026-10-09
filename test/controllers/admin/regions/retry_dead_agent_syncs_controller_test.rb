require "test_helper"
require "minitest/mock"

class Admin::Regions::RetryDeadAgentSyncsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    @region = regions(:regionone)
    @project = deployments(:project_test)
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_metadata", error: "x")
    Agent::PendingSync.record!(region: @region, project: @project, kind: "managed_ssh_keys", error: "x")
    @dead = AgentPendingSync.find_by(kind: "managed_metadata")
    @dead.update_columns(dead_at: 1.hour.ago, attempts: 24, first_attempted_at: 3.days.ago, next_attempt_at: 1.hour.ago)
  end

  test "the region page offers Retry dead when there are dead syncs" do
    get "/admin/regions/#{@region.id}"
    assert_response :success
    assert_select "a[href='/admin/regions/#{@region.id}/retry_dead_agent_syncs']"
  end

  test "retry dead revives the dead rows with a fresh budget and enqueues a replay" do
    enqueued = []
    AgentWorkers::PendingSyncWorker.stub(:perform_async, ->(*args) { enqueued << args }) do
      post "/admin/regions/#{@region.id}/retry_dead_agent_syncs"
    end
    assert_redirected_to "/admin/regions/#{@region.id}"
    @dead.reload
    assert_nil @dead.dead_at
    assert_equal 0, @dead.attempts
    assert_nil @dead.first_attempted_at
    assert_in_delta Time.current, @dead.next_attempt_at, 5
    assert_equal [[@region.id]], enqueued
  end
end
