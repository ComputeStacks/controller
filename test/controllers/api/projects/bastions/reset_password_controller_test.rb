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
  end

  test "reports an error and keeps the password when the node is offline" do
    @sftp.node.update!(maintenance: true)

    post @path, as: :json, headers: @basic_auth_headers

    assert_response :unprocessable_entity
    refute_empty JSON.parse(response.body)["errors"]
    assert_equal @old_password, @sftp.reload.password
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
