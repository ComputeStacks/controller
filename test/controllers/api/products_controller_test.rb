require 'test_helper'

class Api::ProductsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can view pricing' do
    get "/api/products", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
