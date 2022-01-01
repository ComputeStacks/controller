require 'test_helper'

class Api::Admin::Users::SshKeysControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  def before_setup
    super
    @end_user = User.find_by(email: 'a@example.local')
  end

  test "list ssh keys" do

    get "/api/admin/users/#{@end_user.id}/ssh_keys", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

  test 'create ssh key' do

    k = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDl6+KP0+AK14bBdS0s+hIey/Jg7l9ijNSTrIn/99lA+ CS-support"

    post "/api/admin/users/#{@end_user.id}/ssh_keys", params: {
      user_ssh_key: { pubkey: k }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "CS-support", data['user_ssh_key']['label']
    assert_equal @end_user.ssh_keys.first.id, data['user_ssh_key']['id']

  end

end
