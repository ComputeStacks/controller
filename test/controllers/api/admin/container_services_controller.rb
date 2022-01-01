require 'test_helper'

class Api::Admin::ContainerServicesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'list all container services' do

    get "/api/admin/container_services", as: :json, headers: @basic_auth_headers
    assert_response :success

  end

end
