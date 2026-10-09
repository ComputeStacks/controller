require "test_helper"

class Api::Containers::PowerControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @container = deployment_containers(:pma_1)
    @node = @container.node
    @path = "/api/containers/#{@container.id}/power/restart"
  end

  test "a queued action responds 202 with its event" do
    put @path, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal false, data["deferred"]
    assert_equal "pending", EventLog.find(data["event_id"]).status
    refute data.key?("code")
  end

  test "an action on a node in maintenance is deferred" do
    @node.update_columns(maintenance_requested: true)

    put @path, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal true, data["deferred"]
    assert_equal "node_maintenance", data["code"]
    assert_equal "maintenance", data["node_status"]["state"]
    assert_equal "deferred", data["node_status"]["operations"]["power"]
    event = EventLog.find(data["event_id"])
    assert_equal "pending", event.status
    assert event.labels["deferred_action"].present?
  end

  test "an action on an offline node is refused with 409" do
    @node.update_columns(disconnected: true, disconnected_at: 5.minutes.ago)

    put @path, headers: @basic_auth_headers

    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_offline", data["code"]
    assert_equal "offline", data["node_status"]["state"]
    refute_empty data["errors"]
  end

  test "an action on a container with no node is refused with 409" do
    @container.update_columns(node_id: nil)

    put @path, headers: @basic_auth_headers

    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_offline", data["code"]
    assert_equal "offline", data["node_status"]["state"]
  end

  test "the 409 renders as xml too" do
    @node.update_columns(disconnected: true)

    put @path, headers: @basic_auth_headers.merge("Accept" => "application/xml; api_version=65;")

    assert_response :conflict
    assert_match(/<code>node_offline<\/code>/, response.body)
  end

  test "an unknown action is still a 422" do
    put "/api/containers/#{@container.id}/power/explode", headers: @basic_auth_headers

    assert_response :unprocessable_entity
  end
end
