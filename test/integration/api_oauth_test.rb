require 'test_helper'
# require 'oauth2'

class ApiOauthTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'oauth via client credentials' do
    app = Doorkeeper::Application.find_by(name: 'admin')
    @headers['Authorization'] = ActionController::HttpAuthentication::Basic.encode_credentials(
      app.uid, 
      app.secret
    )
    post "/api/oauth/token", params: {
      scope: 'public',
      grant_type: 'client_credentials'
    }, as: :json, headers: @headers

    assert_response :success
    
    # {
    #   "access_token":"_RNtQXAPdRsFjqUz_HOxGeKU1ygTlnhjc7k8k9FAM5o",
    #   "token_type":"Bearer",
    #   "expires_in":7200,
    #   "scope":"public",
    #   "created_at":1568333288
    # }
    init_response = JSON.parse(response.body)

    assert_not_nil init_response['access_token']
    assert_equal init_response['scope'], 'public'
    assert_equal init_response['token_type'], 'Bearer'

    @headers['Authorization'] = "Bearer #{init_response['access_token']}"
    get "/api/version", as: :json, headers: @headers

    assert_response :success

    rsp = JSON.parse(response.body)

    assert_equal COMPUTESTACKS_VERSION, rsp['version']    

  end

  test 'oauth via username password' do
    app = Doorkeeper::Application.find_by(name: 'admin')
    @headers['Authorization'] = ActionController::HttpAuthentication::Basic.encode_credentials(
      app.uid, 
      app.secret
    )
    
    api_auth = User::ApiCredential.find_by(name: 'admin')
    assert_not_nil api_auth

    post "/api/oauth/token", params: {
      username: api_auth.username,
      password: 've2YAixq2eh6bboq0qPVjMOC',
      scope: 'public',
      grant_type: 'password'
    }, as: :json, headers: @headers

    assert_response :success
    
    # {
    #   "access_token":"_RNtQXAPdRsFjqUz_HOxGeKU1ygTlnhjc7k8k9FAM5o",
    #   "token_type":"Bearer",
    #   "expires_in":7200,
    #   "scope":"public",
    #   "created_at":1568333288
    # }
    init_response = JSON.parse(response.body)

    assert_not_nil init_response['access_token']
    assert_equal init_response['scope'], 'public'
    assert_equal init_response['token_type'], 'Bearer'

    @headers['Authorization'] = "Bearer #{init_response['access_token']}"
    get "/api/version", as: :json, headers: @headers

    assert_response :success

    rsp = JSON.parse(response.body)

    assert_equal COMPUTESTACKS_VERSION, rsp['version']    

  end

  # Test if a non-admin can grab admin scope.
  test 'oauth admin escalation' do
    # Admin app, but non-admin user.
    app = Doorkeeper::Application.find_by(name: 'admin')
    @headers['Authorization'] = ActionController::HttpAuthentication::Basic.encode_credentials(
      app.uid, 
      app.secret
    )
    
    api_auth = User::ApiCredential.find_by(name: 'user')
    assert_not_nil api_auth

    post "/api/oauth/token", params: {
      username: api_auth.username,
      password: '4Xv7ixq2eh6bboq0qPVjhBg',
      scope: 'admin_read admin_write',
      grant_type: 'password'
    }, as: :json, headers: @headers

    assert_response 403   

  end

  # Test if a admin can grab admin scope.
  test 'oauth admin request' do
    # Admin app, but non-admin user.
    app = Doorkeeper::Application.find_by(name: 'admin')
    @headers['Authorization'] = ActionController::HttpAuthentication::Basic.encode_credentials(
      app.uid, 
      app.secret
    )
    
    api_auth = User::ApiCredential.find_by(name: 'admin')
    assert_not_nil api_auth

    post "/api/oauth/token", params: {
      username: api_auth.username,
      password: 've2YAixq2eh6bboq0qPVjMOC',
      scope: 'admin_read admin_write',
      grant_type: 'password'
    }, as: :json, headers: @headers

    assert_response :success   

  end

end