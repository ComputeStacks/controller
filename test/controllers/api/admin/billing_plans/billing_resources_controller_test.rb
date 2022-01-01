require 'test_helper'

class Api::Admin::BillingPlans::BillingResourcesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list all' do

    get "/api/admin/billing_plans/#{billing_plans(:default).id}/billing_resources", as: :json, headers: @basic_auth_headers

    assert_response :success
    # data = JSON.parse(response.body)
    # assert_not_empty data['user_groups']

  end
end
