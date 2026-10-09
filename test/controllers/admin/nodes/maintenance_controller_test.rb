require "test_helper"
require "minitest/mock"

class Admin::Nodes::MaintenanceControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_reason: nil, maintenance_gen: 0,
      maintenance_override_gen: nil, maintenance_holds: {}, maintenance_status: {}, job_status: "idle")
    @path = "/admin/nodes/#{@node.id}/maintenance"
    AgentWorkers::PushMaintenanceWorker.jobs.clear
    NodeWorkers::EvacuateNodeWorker.jobs.clear
  end

  # The drift worker belongs to another part of this change and may not be loaded
  # here; stand one in only when it is missing, and take it away again after.
  def with_drift_worker(fake)
    created = false
    unless AgentWorkers.const_defined?(:MaintenanceDriftWorker)
      AgentWorkers.const_set(:MaintenanceDriftWorker, Class.new { def refresh!(_node) = raise(NotImplementedError) })
      created = true
    end
    AgentWorkers::MaintenanceDriftWorker.stub(:new, fake) { yield }
  ensure
    AgentWorkers.send(:remove_const, :MaintenanceDriftWorker) if created
  end

  test "enter places the controller hold with a reason, through the service" do
    assert_difference -> { Audit.count }, 1 do
      post @path, params: {reason: "kernel"}
    end

    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    @node.reload
    assert @node.maintenance_requested
    assert @node.maintenance
    assert_equal "kernel", @node.maintenance_reason
    assert_equal 1, @node.maintenance_gen
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
    assert_empty NodeWorkers::EvacuateNodeWorker.jobs, "no clustered storage, so no evacuation"
  end

  test "enter with a customer message sets the notice once the node is in maintenance" do
    @node.update_columns(customer_notice: nil)

    post @path, params: {reason: "kernel", customer_message: "Back within the hour"}

    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    assert_match "Maintenance requested", flash[:notice]
    @node.reload
    assert @node.maintenance
    assert_equal "kernel", @node.maintenance_reason
    assert_equal "Back within the hour", @node.customer_notice
  end

  test "enter evacuates on clustered storage, but only when the hold changed" do
    original = Region.instance_method(:has_clustered_storage?)
    Region.define_method(:has_clustered_storage?) { true }
    begin
      post @path
      post @path
    ensure
      Region.define_method(:has_clustered_storage?, original)
    end
    assert_equal 1, NodeWorkers::EvacuateNodeWorker.jobs.size
    assert_equal 1, @node.reload.maintenance_gen
  end

  test "release drops the controller hold and says when the node still holds itself" do
    @node.update_columns(maintenance_requested: true, maintenance_gen: 1, job_status: "evacuating",
      maintenance_holds: {"local" => {"reason" => "docker-upgrade", "by" => "root"}})

    delete @path

    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    assert_match "still held in maintenance by the node", flash[:notice]
    @node.reload
    refute @node.maintenance_requested
    assert @node.maintenance, "the node's own hold keeps it in maintenance"
    assert_equal 2, @node.maintenance_gen
    assert_equal "idle", @node.job_status
  end

  test "override releases both holds and arms the override generation" do
    @node.update_columns(maintenance_gen: 3, maintenance_holds: {"local" => {"reason" => "forgotten"}})

    assert_difference -> { SystemEvent.count }, 1 do
      post "#{@path}/release_all"
    end

    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    @node.reload
    assert_equal 4, @node.maintenance_gen
    assert_equal 4, @node.maintenance_override_gen
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
  end

  test "refresh asks the drift worker to GET and project the agent's state" do
    seen = []
    fake = Object.new
    fake.define_singleton_method(:refresh!) { |node| seen << node.id; :ok }

    with_drift_worker(fake) { post "#{@path}/refresh" }

    assert_equal [@node.id], seen
    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    assert_match "Refreshed", flash[:notice]
  end

  test "refresh explains each non-ok result" do
    {locked: "try again shortly", unreachable: "could not reach", unsupported: "older than 3.4", error: "unexpected response"}.each do |result, text|
      fake = Object.new
      fake.define_singleton_method(:refresh!) { |_node| result }

      with_drift_worker(fake) { post "#{@path}/refresh" }

      assert_redirected_to "/admin/nodes/#{@node.id}/edit"
      assert_match text, flash[:alert]
    end
  end

  test "refresh reports an exception rather than raising" do
    fake = Object.new
    fake.define_singleton_method(:refresh!) { |_node| raise Errno::ECONNREFUSED }

    with_drift_worker(fake) { post "#{@path}/refresh" }

    assert_redirected_to "/admin/nodes/#{@node.id}/edit"
    assert_match "Could not reach", flash[:alert]
  end

  test "refresh without an agent token does not call the agent" do
    @node.update_columns(agent_token_encrypted: nil)
    fake = Object.new
    fake.define_singleton_method(:refresh!) { |_node| flunk "should not be called" }

    with_drift_worker(fake) { post "#{@path}/refresh" }

    assert_match "no agent token", flash[:alert]
  end

  test "the edit page shows the hold, the actions, and the override only for a node hold" do
    get "/admin/nodes/#{@node.id}/edit"
    assert_response :success
    assert_match "Enter Maintenance", response.body
    assert_no_match "Override: Release All Holds", response.body
    assert_match "Refresh from Agent", response.body

    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel",
      maintenance_holds: {"local" => {"reason" => "docker-upgrade", "by" => "root"}})
    get "/admin/nodes/#{@node.id}/edit"
    assert_response :success
    assert_match "Release Controller Hold", response.body
    assert_match "Override: Release All Holds", response.body
    assert_match "held by controller (kernel) and node (docker-upgrade)", response.body
  end

  test "the events page has a maintenance status header" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_updated: Time.now)

    get "/admin/nodes/#{@node.id}/events"

    assert_response :success
    assert_match "In Maintenance (controller)", response.body
    assert_match "held by controller (kernel)", response.body
  end

  test "the AZ and location pages summarize maintenance and pending syncs" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel")
    AgentPendingSync.create!(region: @node.region, project_id: 1, kind: "tenant", first_failed_at: 2.hours.ago)

    get "/admin/regions/#{@node.region_id}"
    assert_response :success
    assert_match "1 of 1 node in maintenance", response.body
    assert_match "1 agent sync pending", response.body

    get "/admin/locations/#{@node.region.location_id}"
    assert_response :success
    assert_match "<th>Maintenance</th>", response.body
    assert_match ">controller<", response.body

    get "/admin/locations"
    assert_response :success
    assert_match "In Maintenance", response.body
  end
end
