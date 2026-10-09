require "test_helper"

##
# Backup, backup delete, restore and export refuse with 409 and a `code` when the volume's
# node is in maintenance or offline; the event is still created and failed as before.
class Api::Volumes::NodeUnavailableTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  setup do
    @volume = volumes(:mysql)
    @node = nodes(:testone)
    @archive = Base64.urlsafe_encode64("nightly-1")
    CallbackWorker.clear
  end

  def requests
    {
      backup: -> { post "/api/volumes/#{@volume.id}/backups", params: {name: "manual-backup", callback: {url: "https://cb.example/hook", authorization: "Bearer x"}}.to_json, headers: @basic_auth_headers },
      backup_delete: -> { delete "/api/volumes/#{@volume.id}/backups/#{@archive}", headers: @basic_auth_headers },
      restore: -> { post "/api/volumes/#{@volume.id}/restore", params: {name: "nightly-1"}.to_json, headers: @basic_auth_headers },
      export: -> { post "/api/volumes/#{@volume.id}/exports", params: {id: @archive}.to_json, headers: @basic_auth_headers }
    }
  end

  test "a node in maintenance refuses each operation with 409 node_maintenance" do
    @node.update_columns(maintenance_requested: true)
    requests.each do |op, request|
      assert_difference "EventLog.where(status: 'failed').count", 1, "#{op} should fail its event" do
        request.call
      end
      assert_response :conflict, op.to_s
      data = JSON.parse(response.body)
      assert_equal "node_maintenance", data["code"], op.to_s
      assert_equal "maintenance", data["node_status"]["state"], op.to_s
      assert_match(/in maintenance/, data["errors"].first, op.to_s)
      assert_equal "node_maintenance", EventLog.where(status: "failed").order(:id).last.result_code, op.to_s
    end
    # The backup's callback still reports the failure.
    assert_equal 1, CallbackWorker.jobs.size
  end

  test "an offline node refuses each operation with 409 node_offline" do
    @node.update_columns(disconnected: true)
    requests.each do |op, request|
      request.call
      assert_response :conflict, op.to_s
      data = JSON.parse(response.body)
      assert_equal "node_offline", data["code"], op.to_s
      assert_equal "offline", data["node_status"]["state"], op.to_s
      assert_equal "node_offline", EventLog.where(status: "failed").order(:id).last.result_code, op.to_s
    end
  end

  test "a volume with no node refuses with 409 node_offline" do
    @volume.nodes.clear
    requests[:backup].call
    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_offline", data["code"]
    assert_equal "offline", data["node_status"]["state"]
    assert_match(/not assigned to a node/, data["errors"].first)
  end

  test "the 409 renders as xml" do
    @node.update_columns(maintenance_requested: true)
    post "/api/volumes/#{@volume.id}/restore", params: {name: "nightly-1"}.to_json,
      headers: @basic_auth_headers.merge("Accept" => "application/xml; api_version=65;")
    assert_response :conflict
    assert_match(/<code>node_maintenance<\/code>/, response.body)
  end
end
