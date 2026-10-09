require "test_helper"

class Api::Admin::Locations::Regions::NodesControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  test "can list all" do
    get "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes", as: :json, headers: @basic_auth_headers

    assert_response :success
    # data = JSON.parse(response.body)
    # assert_not_empty data['user_groups']
  end

  # agent_host must survive the round trip: permitted on update AND rendered on read.
  # Dropping either the strong-params entry or the rabl attribute would otherwise be silent.
  test "agent_host can be set over the api and is rendered back" do
    node = nodes(:testone)
    assert_nil node.agent_host

    patch "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}",
      params: {node: {agent_host: "100.64.79.114"}}, as: :json, headers: @basic_auth_headers

    assert_response :success
    assert_equal "100.64.79.114", node.reload.agent_host
    assert_equal "100.64.79.114", JSON.parse(response.body)["node"]["agent_host"]
    assert_equal "100.64.79.114", node.agent_address
  end

  test "an invalid agent_host is rejected rather than stored" do
    node = nodes(:testone)

    patch "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}",
      params: {node: {agent_host: "http://100.64.79.114:8500"}}, as: :json, headers: @basic_auth_headers

    assert_nil node.reload.agent_host
    assert_equal node.primary_ip, node.agent_address
  end

  test "show includes customer_notice and the customer-facing status" do
    node = nodes(:testone)
    node.update_columns(maintenance_requested: true, maintenance_updated: 1.hour.ago, customer_notice: "Back soon")

    get "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)["node"]
    assert_equal "Back soon", data["customer_notice"]
    assert_equal "maintenance", data["customer_status"]["state"]
    assert_equal "Back soon", data["customer_status"]["message"]
  end

  test "customer_notice is set through the notice service, audited, alongside other fields" do
    node = nodes(:testone)
    node.update_columns(disconnected: true, disconnected_at: 10.minutes.ago, customer_notice: nil)

    assert_difference -> { Audit.count }, 2 do # the notice, then the node update
      patch "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}",
        params: {node: {customer_notice: "Investigating a network outage", label: "renamed"}}, as: :json, headers: @basic_auth_headers
    end

    assert_response :success
    data = JSON.parse(response.body)["node"]
    assert_equal "Investigating a network outage", data["customer_notice"]
    assert_equal "Investigating a network outage", data["customer_status"]["message"]
    assert_equal "renamed", data["label"]
    assert_equal "Investigating a network outage", node.reload.customer_notice

    patch "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}",
      params: {node: {customer_notice: ""}}, as: :json, headers: @basic_auth_headers

    assert_response :success
    assert_nil node.reload.customer_notice
  end

  test "setting customer_notice on an online node is refused with 422 and changes nothing" do
    node = nodes(:testone)
    node.update_columns(disconnected: false, maintenance_requested: false, maintenance_holds: {}, customer_notice: nil)

    patch "/api/admin/locations/#{locations(:testlocation).id}/regions/#{regions(:regionone).id}/nodes/#{node.id}",
      params: {node: {customer_notice: "Hello", label: "renamed"}}, as: :json, headers: @basic_auth_headers

    assert_response :unprocessable_entity
    assert_match(/only be set while the node is in maintenance or offline/, JSON.parse(response.body)["errors"].first)
    node.reload
    assert_nil node.customer_notice
    refute_equal "renamed", node.label
  end
end
