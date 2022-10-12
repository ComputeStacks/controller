require 'test_helper'

class Api::LocationsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "list locations" do

    get "/api/locations", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)
    refute_empty data['locations']
  end

end
