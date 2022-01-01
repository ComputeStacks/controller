require 'test_helper'

class Api::Users::SshKeysControllerTest < ActionDispatch::IntegrationTest

  def before_setup
    super
    @user = User.find_by(email: 'a@example.local')
    cred = @user.api_credentials.first
    @basic_auth_headers = {
      'Accept' => 'application/json; api_version=65;',
      'Content-Type' => 'application/json',
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(
        cred.username,
        "4Xv7ixq2eh6bboq0qPVjhBg"
      )
    }
  end

  test "list ssh keys" do

    get "/api/users/ssh_keys", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

  test 'create ssh key' do

    k = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDl6+KP0+AK14bBdS0s+hIey/Jg7l9ijNSTrIn/99lA+ CS-support"

    post "/api/users/ssh_keys", params: {
      user_ssh_key: { pubkey: k }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "CS-support", data['ssh_key']['label']

  end

end
