require 'test_helper'

class Api::ContainerServices::ContainersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "can list containers" do

    get "/api/container_services/#{deployment_container_services(:wordpress).id}/containers", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['containers']

    assert data['containers'].first['on_latest_image']

  end
end
