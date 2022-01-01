require 'test_helper'

class Api::UsersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "view my api user info" do

    get "/api/users", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)

    # Ensure we get the correct user data!
    assert_equal users(:admin).email, data['user']['email']

    refute_nil data['user']['unprocessed_usage']

  end

  test 'create demo user' do

    # Request token via client credentails
    oauth_app = Doorkeeper::Application.find_by(name: 'user')
    assert_not_nil oauth_app

    post "/api/oauth/token", params: {
      scope:      'public register',
      grant_type: 'client_credentials'
    },
       as:                         :json,
       headers:                    {
         'Accept'        => 'application/json; api_version=51;',
         'Content-Type'  => 'application/json',
         'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(
           oauth_app.uid,
           oauth_app.secret
         )
       }

    assert_response :success
    token_response = JSON.parse(response.body)

    access_token = token_response['access_token']

    assert !access_token.blank?

    create_fname             = 'Joee'
    create_lname             = 'Smithers'
    create_provider_server   = 'test01'
    create_provider_username = 'jsmithers'

    post "/api/users", params: {
      user:              {
        fname: create_fname,
        lname: create_lname,
        locale: 'foo',
        currency: 'eur'
      },
      provider_server:   create_provider_server,
      provider_username: create_provider_username
    },
       as:                   :json,
       headers:              {
         'Accept'        => 'application/json; api_version=51;',
         'Content-Type'  => 'application/json',
         'Authorization' => "Bearer #{access_token}"
       }

    assert_response :success

    user_data = JSON.parse(response.body)

    assert !user_data['user']['email'].blank?

    new_user = User.find_by(email: user_data['user']['email'])
    assert_not_nil new_user
    assert_not_empty new_user.api_credentials

    assert_equal 'en', new_user.locale
    assert_equal 'EUR', new_user.currency
    assert_equal 'EUR', user_data['user']['currency']

    assert_equal create_fname, new_user.fname
    assert_equal create_lname, new_user.lname
    assert_equal create_provider_username, new_user.labels['cpanel'][create_provider_server]

    api_cred = new_user.api_credentials.first

    assert_equal user_data['user']['api']['username'], api_cred.username

    # Ensure our credentials are active
    get "/api/users", as: :json, headers: {
      'Accept'        => 'application/json; api_version=51;',
      'Content-Type'  => 'application/json',
      'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(
        user_data['user']['api']['username'],
        user_data['user']['api']['password']
      )
    }

    assert_response :success

  end

end
