require 'test_helper'

class Api::Admin::LocationsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list all' do

    get "/api/admin/locations", as: :json, headers: @basic_auth_headers

    assert_response :success
    # data = JSON.parse(response.body)
    # assert_not_empty data['user_groups']

  end
end
