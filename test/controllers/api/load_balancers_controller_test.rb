require 'test_helper'

class Api::LoadBalancersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list load balancers' do
    get "/api/load_balancers", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
