require 'test_helper'

class Api::SubscriptionsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list subscriptions' do
    get "/api/subscriptions", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
