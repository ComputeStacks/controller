require 'test_helper'

class Api::ContainerServicesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "can list container services" do

    VCR.use_cassette('controllers/api/container_services/index') do
      get "/api/container_services", as: :json, headers: @basic_auth_headers

      assert_response :success

      data = JSON.parse(response.body)

      refute_empty data['container_services']
    end

  end

  test "can view container services" do

    VCR.use_cassette('controllers/api/container_services/show') do
      get "/api/container_services/#{deployment_container_services(:wordpress).id}", as: :json, headers: @basic_auth_headers

      assert_response :success

      data = JSON.parse(response.body)

      refute_nil data['container_service']
    end

  end


end
