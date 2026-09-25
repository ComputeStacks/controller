require "test_helper"

class Admin::Sftp::PasswordControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    @sftp = deployment_sftp(:project_test_testone)
  end

  test "admin can rotate the ssh password" do
    old_password = @sftp.password

    post "/admin/sftp/#{@sftp.id}/password"

    assert_redirected_to "/admin/sftp/#{@sftp.id}"
    assert_equal "SSH password rotated. It takes effect once the SSH container rebuild completes.", flash[:notice]
    refute_equal old_password, @sftp.reload.password
  end

  test "sftp page offers rotation outside the password cell" do
    get "/admin/sftp/#{@sftp.id}"

    assert_response :success
    rotate = "a[data-method=post][data-confirm][href='/admin/sftp/#{@sftp.id}/password']"
    assert_select rotate, text: "Rotate"
    assert_select "td#sftp-password #{rotate}", count: 0
  end
end
