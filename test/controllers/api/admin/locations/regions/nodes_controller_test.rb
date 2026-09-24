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
end
