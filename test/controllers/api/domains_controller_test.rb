require 'test_helper'

class Api::DomainsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list project domains' do
    get "/api/domains", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
