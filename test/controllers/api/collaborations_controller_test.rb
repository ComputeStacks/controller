require 'test_helper'

class Api::CollaborationsControllerTest < ActionDispatch::IntegrationTest

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

  test "list collaborations" do

    get "/api/collaborations", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_kind_of Array, data['projects']
    assert_kind_of Array, data['domains']
    assert_kind_of Array, data['images']
    assert_kind_of Array, data['registries']

  end

end
