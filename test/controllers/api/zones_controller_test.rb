require 'test_helper'

class Api::ZonesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list dns zones' do
    get "/api/zones", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
