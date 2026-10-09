require "test_helper"

class Api::Projects::Bastions::ResetPasswordControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  # ApiTestControllerBase sets the auth headers in before_setup, after `setup` blocks run.
  def before_setup
    super
    @sftp = deployment_sftp(:project_test_testone)
    @deployment = @sftp.deployment
    @path = "/api/projects/#{@deployment.id}/bastions/#{@sftp.id}/reset_password"
    @old_password = @sftp.password
    @user_auth_headers = @basic_auth_headers.merge(
      "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
        user_api_credentials(:user).username,
        "4Xv7ixq2eh6bboq0qPVjhBg"
      )
    )
  end

  test "resets the password and returns the new one" do
    post @path, as: :json, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    new_password = @sftp.reload.password
    refute_equal @old_password, new_password
    assert_equal @sftp.id, data["bastion"]["id"]
    assert_equal new_password, data["bastion"]["password"]

    event = EventLog.find(data["event_id"])
    assert_equal "container.rebuild", event.locale
    assert_includes event.sftp_containers, @sftp
    assert_nil event.labels["callback_url"]
    assert_nil event.labels["callback_auth"]
  end

  test "stores the callback on the rebuild event" do
    callback = {authorization: "Bearer abc123", url: "https://integration.example.com/api/webhooks/task/42"}
    post @path, params: {callback: callback}, as: :json, headers: @basic_auth_headers

    assert_response :accepted
    event = EventLog.find(JSON.parse(response.body)["event_id"])
    assert_equal callback[:url], event.labels["callback_url"]
    assert_equal callback[:authorization], event.labels["callback_auth"]
  end

  test "rejects a malformed callback without changing anything" do
    [{callback: "https://integration.example.com"}, {callback: {url: {nested: true}}}].each do |body|
      assert_no_difference "EventLog.count" do
        post @path, params: body, as: :json, headers: @basic_auth_headers
      end
      assert_response :unprocessable_entity
      assert_equal @old_password, @sftp.reload.password
    end
  end

  test "refuses with 409 node_maintenance and keeps the password when the node is in maintenance" do
    @sftp.node.update!(maintenance_requested: true)

    post @path, as: :json, headers: @basic_auth_headers

    assert_response :conflict
    data = JSON.parse(response.body)
    refute_empty data["errors"]
    assert_equal "node_maintenance", data["code"]
    assert_equal "maintenance", data["node_status"]["state"]
    assert_equal "refused", data["node_status"]["operations"]["bastion_password_reset"]
    assert_equal @old_password, @sftp.reload.password
  end

  test "refuses with 409 node_offline when the node is offline" do
    @sftp.node.update_columns(disconnected: true)

    post @path, as: :json, headers: @basic_auth_headers

    assert_response :conflict
    data = JSON.parse(response.body)
    assert_equal "node_offline", data["code"]
    assert_equal "offline", data["node_status"]["state"]
    assert_equal @old_password, @sftp.reload.password
  end

  test "another action in progress is still a 422" do
    busy = EventLog.create!(locale: "container.restart", status: "running", event_code: "d611b2bbf50bd48c")
    busy.sftp_containers << @sftp

    post @path, as: :json, headers: @basic_auth_headers

    assert_response :unprocessable_entity
    refute JSON.parse(response.body).key?("code")
  end

  test "returns not found for a user without access to the project" do
    post @path, as: :json, headers: @user_auth_headers

    assert_response :not_found
    assert_equal @old_password, @sftp.reload.password
  end

  test "an active collaborator can reset the password" do
    collab = @deployment.deployment_collaborators.new(
      collaborator: users(:user), skip_confirmation: true, current_user: users(:admin)
    )
    assert collab.save, collab.errors.full_messages.join(" ")

    post @path, as: :json, headers: @user_auth_headers

    assert_response :accepted
    refute_equal @old_password, @sftp.reload.password
  end
end
