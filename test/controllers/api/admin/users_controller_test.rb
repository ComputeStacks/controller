require 'test_helper'

class Api::Admin::UsersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list all users' do
    get "/api/admin/users", as: :json, headers: @basic_auth_headers
    assert_response :success

    data = JSON.parse(response.body)

    assert_not_empty data['users']

    assert_nil data['users'].first['unprocessed_usage']
  end

  test 'can list users with usage' do
    get "/api/admin/users?include=balance", as: :json, headers: @basic_auth_headers
    assert_response :success

    data = JSON.parse(response.body)

    assert_not_empty data['users']

    refute_nil data['users'].first['unprocessed_usage']
  end

  test 'can find user by username' do

    email = users(:user).email
    email = Base64.strict_encode64(email)
    get "/api/admin/users/#{email}?find_by_email=true", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal users(:user).email, data['user']['email']

  end

  test 'can find user by whmcs service id' do

    service_id = users(:whmcsuser).labels['whmcs']['service_id']
    get "/api/admin/users/#{service_id}?find_by_label=whmcs_service_id", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal service_id, data['user']['labels']['whmcs']['service_id']

  end

  test 'can see user group' do
    get "/api/admin/users/#{users(:user).id}", as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_not_empty data['user']['user_group']
    assert_equal users(:user).user_group_id, data['user']['user_group']['id']
  end

  test 'can create user with non-default group' do
    pass = SecureRandom.base64
    fake_user = {
      'user' => {
        'fname' => 'Foo',
        'lname' => 'Barr',
        'password' => pass,
        'password_confirmation' => pass,
        'skip_email_confirm' => true,
        'email' => 'foobar24@usrtest.net',
        'user_group_id' => user_groups(:testgroup).id
      }
    }

    post "/api/admin/users",  params: fake_user, as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 'foobar24@usrtest.net', data['user']['email']
    assert_equal user_groups(:testgroup).id, data['user']['user_group_id']
  end

  test 'can create user with labels' do
    pass = SecureRandom.base64
    fake_user = {
      'user' => {
        'fname' => 'Foo',
        'lname' => 'Bar',
        'password' => pass,
        'password_confirmation' => pass,
        'skip_email_confirm' => true,
        'email' => 'foobar23@usrtest.net',
        'merge_labels' => {
          'whmcs' => {
            'client_id' => 33,
            'service_id' => 44
          }
        }
      }
    }

    post "/api/admin/users",  params: fake_user, as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal 'foobar23@usrtest.net', data['user']['email']
    assert_equal 44, data['user']['labels']['whmcs']['service_id']

    # find the user and verify it actually saved
    l = User.find_by(email: 'foobar23@usrtest.net').labels['whmcs']
    assert_equal 44, l['service_id']
    assert_equal 33, l['client_id']

  end

  test 'can update existing user labels' do

    # First, Set some labels
    user_path = "/api/admin/users/#{users(:user).id}"
    get user_path, as: :json, headers: @basic_auth_headers
    assert_response :success

    patch user_path, params: {
      'user' => {
        'merge_labels' => {
          'cpanel' => {
            'myserver' => 'myusername'
          }
        }
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success
    assert_equal 'myusername', User.find_by(email: users(:user).email).labels['cpanel']['myserver']

    # Now add some additional labels and ensure they still exist
    patch user_path, params: {
      'user' => {
        'merge_labels' => {
          'whmcs' => {
            'client_id' => 15
          }
        }
      }
    }, as: :json, headers: @basic_auth_headers
    assert_response :success

    l = User.find_by(email: users(:user).email).labels

    # Make sure existing labels still exist
    assert_equal 'myusername', l['cpanel']['myserver']

    # And new labels
    assert_equal 15, l['whmcs']['client_id']

  end

end
