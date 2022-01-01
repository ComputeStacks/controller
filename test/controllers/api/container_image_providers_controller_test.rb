require 'test_helper'

class Api::ContainerImageProvidersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase
  
  test "list container image providers" do

    get "/api/container_image_providers", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal ContainerImageProvider.count, data['container_image_providers'].count  

  end

end
