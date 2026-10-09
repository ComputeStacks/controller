require "test_helper"

class Api::Admin::Locations::Regions::Nodes::MaintenanceReleaseAllControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_gen: 2, maintenance_override_gen: nil,
      maintenance_holds: {"local" => {"since" => 1.hour.ago.utc.iso8601, "reason" => "docker-upgrade", "by" => "root"}})
    @path = "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{@node.id}/maintenance/release_all"
    AgentWorkers::PushMaintenanceWorker.jobs.clear
  end

  test "requires confirm=true and changes nothing without it" do
    assert_no_difference -> { Audit.count } do
      post @path, as: :json, headers: @basic_auth_headers
    end
    assert_response :unprocessable_entity
    assert_match(/confirm=true/, JSON.parse(response.body)["errors"].first)

    post @path, params: {confirm: "false"}, as: :json, headers: @basic_auth_headers
    assert_response :unprocessable_entity

    @node.reload
    assert_equal 2, @node.maintenance_gen
    assert_nil @node.maintenance_override_gen
    assert_empty AgentWorkers::PushMaintenanceWorker.jobs
  end

  test "with confirm, overrides both holds, audited, and reports the override as pending" do
    assert_difference -> { Audit.count } => 1, -> { SystemEvent.count } => 1 do
      post @path, params: {confirm: true}, as: :json, headers: @basic_auth_headers
    end

    assert_response :accepted
    @node.reload
    assert_equal 3, @node.maintenance_gen
    assert_equal 3, @node.maintenance_override_gen
    refute @node.maintenance_requested
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size

    audit = Audit.order(:id).last
    assert_equal "updated", audit.event
    assert_equal user_api_credentials(:admin).user_id, audit.user_id

    body = JSON.parse(response.body)
    assert_equal false, body["maintenance_requested"]
    # The local hold is gone only once the agent applies the override.
    assert_equal true, body["maintenance"]
    assert_includes body["maintenance_status"]["warnings"], "override_pending"
  end

  test "is a standard create, so the admin write scope applies" do
    assert_equal [:admin_write], Api::Admin::Locations::Regions::Nodes::MaintenanceReleaseAllController.api_scope_map["create"]
  end
end
