require "test_helper"

class Api::Admin::Locations::Regions::Nodes::MaintenanceControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_gen: 0, maintenance_holds: {})
    @path = "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{@node.id}/maintenance"
    AgentWorkers::PushMaintenanceWorker.jobs.clear
  end

  test "POST requests the controller hold through the service" do
    assert_difference -> { Audit.count }, 1 do
      post @path, params: {reason: "kernel"}, as: :json, headers: @basic_auth_headers
    end

    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal true, body["maintenance"]
    assert_equal true, body["maintenance_requested"]
    assert_equal 1, body["maintenance_gen"]

    @node.reload
    assert @node.maintenance_requested
    assert_equal "kernel", @node.maintenance_reason
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
    assert_equal true, body["maintenance_status"]["requested"]
    assert_equal "kernel", body["maintenance_status"]["reason"]
    assert_equal ["controller"], @node.maintenance_held_by
  end

  test "DELETE releases the controller hold but reports a node-held node as still in maintenance" do
    @node.update_columns(maintenance_requested: true, maintenance_gen: 3, maintenance_holds: {"local" => {"by" => "root"}})

    delete @path, as: :json, headers: @basic_auth_headers

    assert_response :accepted
    body = JSON.parse(response.body)
    assert_equal false, body["maintenance_requested"]
    assert_equal true, body["maintenance"], "the node's own hold keeps it in maintenance"
    assert_equal 4, body["maintenance_gen"]
    refute @node.reload.maintenance_requested
    assert_equal({"by" => "root"}, body["maintenance_status"]["holds"]["local"])
  end

  test "the older DELETE .../maintenance/{id} form still releases" do
    @node.update_columns(maintenance_requested: true, maintenance_gen: 1)

    delete "#{@path}/#{@node.id}", as: :json, headers: @basic_auth_headers

    assert_response :accepted
    refute @node.reload.maintenance_requested
    assert_equal 2, @node.maintenance_gen
  end

  test "repeating a request is accepted, does not bump the generation, and still pushes" do
    post @path, as: :json, headers: @basic_auth_headers
    post @path, as: :json, headers: @basic_auth_headers

    assert_response :accepted
    assert_equal 1, @node.reload.maintenance_gen
    assert_equal 2, AgentWorkers::PushMaintenanceWorker.jobs.size
  end

  test "POST with customer_message sets the customer notice once the hold is placed" do
    @node.update_columns(customer_notice: nil)

    assert_difference -> { Audit.count }, 2 do # the hold, then the notice
      post @path, params: {reason: "kernel", customer_message: "Scheduled kernel upgrade"}, as: :json, headers: @basic_auth_headers
    end

    assert_response :accepted
    @node.reload
    assert_equal "Scheduled kernel upgrade", @node.customer_notice
    assert_equal "kernel", @node.maintenance_reason
    assert_equal "Scheduled kernel upgrade", Nodes::CustomerStatusPresenter.for_node(@node)["message"]
  end

  test "POST without customer_message leaves an existing notice alone" do
    @node.update_columns(disconnected: true, customer_notice: "Network outage")

    post @path, params: {reason: "kernel"}, as: :json, headers: @basic_auth_headers

    assert_response :accepted
    assert_equal "Network outage", @node.reload.customer_notice
  end
end
