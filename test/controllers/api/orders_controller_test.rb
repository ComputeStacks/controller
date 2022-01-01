require 'test_helper'

class Api::OrdersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list orders' do
    get "/api/orders", as: :json, headers: @basic_auth_headers

    assert_response :success
  end

end
