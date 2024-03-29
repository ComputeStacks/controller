require 'test_helper'

class Api::ProjectsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list projects' do
    get "/api/projects", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)
    refute_empty data['projects']
  end
end
