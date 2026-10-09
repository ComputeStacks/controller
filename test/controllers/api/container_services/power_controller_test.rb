require "test_helper"

class Api::ContainerServices::PowerControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @container = deployment_containers(:pma_1)
    @service = @container.service
    @node = @container.node
    @path = "/api/container_services/#{@service.id}/power/restart"
    CallbackWorker.clear
  end

  def parked_events
    PowerCycleContainerService.parked_events_for(@container)
  end

  test "queued actions respond 202 with per-container results" do
    put @path, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal false, data["deferred"]
    assert_nil data["code"]
    assert_equal [{"id" => @container.id, "event_id" => data["event_ids"].first, "result" => "queued"}], data["containers"]
  end

  test "a node in maintenance defers, and an unplaced container is refused, in one response" do
    @node.update_columns(maintenance_requested: true)
    other = deployment_containers(:wordpress_1)
    other.update_columns(container_service_id: @service.id, node_id: nil)

    put @path, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal true, data["deferred"]
    assert_equal "node_maintenance", data["code"]
    results = data["containers"].to_h { |c| [c["id"], c["result"]] }
    assert_equal({@container.id => "deferred", other.id => "refused_offline"}, results)
    assert_includes data["event_ids"], parked_events.first.id
  end

  test "every container refused because the node is offline is a 409" do
    @node.update_columns(disconnected: true)

    put @path, headers: @basic_auth_headers

    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_offline", data["code"]
    assert_equal "offline", data["node_status"]["state"]
  end

  test "a service with no containers is still a 202" do
    @container.update_columns(container_service_id: deployment_container_services(:wordpress).id)

    put @path, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal [], data["containers"]
    assert_equal [], data["event_ids"]
  end

  test "responds in xml" do
    put @path, headers: @basic_auth_headers.merge("Accept" => "application/xml; api_version=65;")

    assert_response :accepted
    assert_match(/<deferred type="boolean">false<\/deferred>/, response.body)
  end

  test "the callback rides on the parked event and fires when it later completes" do
    @node.update_columns(maintenance_requested: true)
    callback = {authorization: "Bearer abc123", url: "https://integration.example.com/hook"}

    put @path, params: {callback: callback}.to_json, headers: @basic_auth_headers

    assert_response :accepted
    event = parked_events.first
    assert_equal callback[:url], event.labels["callback_url"]
    assert_equal callback[:authorization], event.labels["callback_auth"]
    assert_equal 0, CallbackWorker.jobs.size

    # Maintenance ends: the parked action runs on the same event, callback intact.
    @node.update_columns(maintenance_requested: false)
    ContainerWorkers::DeferredPowerWorker.new.perform(@node.id)
    event.reload
    assert_equal "pending", event.status
    assert_nil event.labels["deferred_action"]
    assert_equal callback[:url], event.labels["callback_url"]
    assert_equal 0, CallbackWorker.jobs.size

    event.done!
    assert_equal 1, CallbackWorker.jobs.size
    payload = CallbackWorker.jobs.first["args"].first
    assert_equal event.id, payload["event_id"]
    assert_equal callback[:url], payload["callback"]["url"]
  end

  test "a superseded parked request fires its callback as a failure" do
    @node.update_columns(maintenance_requested: true)
    callback = {authorization: "Bearer abc123", url: "https://integration.example.com/hook"}
    put @path, params: {callback: callback}.to_json, headers: @basic_auth_headers
    first = parked_events.first

    put "/api/containers/#{@container.id}/power/stop", headers: @basic_auth_headers

    assert_response :accepted
    first.reload
    assert_equal "cancelled", first.status
    assert_equal "Superseded", first.state_reason
    assert_equal "superseded", first.result_code
    refute first.success?
    assert_equal [first.id], CallbackWorker.jobs.map { |j| j["args"].first["event_id"] }
  end
end
