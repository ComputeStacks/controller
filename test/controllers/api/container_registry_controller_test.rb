require 'test_helper'

class Api::ContainerRegistryControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list container registries' do
    get "/api/container_registry", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
