require "test_helper"

class Deployments::SftpControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    @sftp = deployment_sftp(:user_project_test_testone)
    @deployment = @sftp.deployment
    sign_in @deployment.user
  end

  test "project owner can rotate the ssh password" do
    old_password = @sftp.password

    post "/deployments/#{@deployment.token}/sftp/#{@sftp.id}/password"

    assert_redirected_to "/deployments/#{@deployment.token}"
    assert_equal "SSH password rotated. It takes effect once the SSH container rebuild completes.", flash[:notice]
    refute_equal old_password, @sftp.reload.password
  end

  test "rotation failure is reported and the password is kept" do
    old_password = @sftp.password
    @sftp.node.update!(maintenance: true)

    post "/deployments/#{@deployment.token}/sftp/#{@sftp.id}/password"

    assert_redirected_to "/deployments/#{@deployment.token}"
    assert flash[:alert].present?
    assert_equal old_password, @sftp.reload.password
  end

  test "connect page offers rotation outside the password cell" do
    service = deployment_container_services(:user_nginx)
    get "/container_services/#{service.id}/connect"

    assert_response :success
    rotate = "a[data-method=post][data-confirm][href='/deployments/#{@deployment.token}/sftp/#{@sftp.id}/password']"
    assert_select rotate, text: "Rotate"
    assert_select "td#sftp-password #{rotate}", count: 0
  end

  test "connect page hides rotation when password auth is off" do
    @sftp.update_column(:pw_auth, false)
    service = deployment_container_services(:user_nginx)
    get "/container_services/#{service.id}/connect"

    assert_response :success
    assert_select "a[data-method=post][href='/deployments/#{@deployment.token}/sftp/#{@sftp.id}/password']", count: 0
  end
end
