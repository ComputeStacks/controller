require "test_helper"

class Api::ContainerServices::ScaleControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @service = deployment_container_services(:pma)
    @node = nodes(:testone)
    @path = "/api/container_services/#{@service.id}/scale"
    ContainerServiceWorkers::ScaleServiceWorker.clear
  end

  def scale_to(qty)
    post @path, params: {container_service: {qty: qty}}.to_json, headers: @basic_auth_headers
  end

  test "scaling up with an available node is accepted" do
    scale_to(@service.containers.count + 1)

    assert_response :accepted
    assert_equal 1, ContainerServiceWorkers::ScaleServiceWorker.jobs.size
  end

  test "scaling up while the region's node is in maintenance is refused with 409" do
    @node.update_columns(maintenance_requested: true)

    assert_no_difference "EventLog.count" do
      scale_to(@service.containers.count + 1)
    end

    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_maintenance", data["code"]
    assert_equal "maintenance", data["node_status"]["state"]
    assert_equal "refused", data["node_status"]["operations"]["scale"]
    assert_equal 0, ContainerServiceWorkers::ScaleServiceWorker.jobs.size
  end

  test "scaling up while the region's node is offline is refused with 409" do
    @node.update_columns(disconnected: true)

    scale_to(@service.containers.count + 1)

    assert_response :conflict
    assert_equal "node_offline", JSON.parse(response.body)["code"]
  end

  test "scaling down is not refused by maintenance" do
    @node.update_columns(maintenance_requested: true)
    deployment_containers(:wordpress_1).update_columns(container_service_id: @service.id)

    scale_to(1)

    assert_response :accepted
    assert_equal 1, ContainerServiceWorkers::ScaleServiceWorker.jobs.size
  end
end
