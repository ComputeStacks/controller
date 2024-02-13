require 'test_helper'

class Api::ContainerServices::BastionsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "can list bastions" do

    get "/api/container_services/#{deployment_container_services(:wordpress).id}/bastions", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['bastions']

    assert data['bastions'].first['on_latest_image']

  end
end
