require 'test_helper'

class Api::ContainerImages::EnvParamsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase
  
  setup do
    @image = ContainerImage.find_by(name: 'custom')
  end

  test "list environmental parameters" do

    get "/api/container_images/#{@image.id}/env_params", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal @image.env_params.count, data['env_params'].count

  end

  test "view environmental parameter" do

    setting = @image.env_params.first

    get "/api/container_images/#{@image.id}/env_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal setting.value, data['env_param']['env_value']

  end

  test "create environmental parameter" do

    post "/api/container_images/#{@image.id}/env_params", params: {
      env_param: {
        name: "MY_SETTING",
        param_type: "static",
        static_value: "myval"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "myval", data['env_param']['static_value']    

  end

  test "update enviornmental parameter" do

    setting = @image.env_params.find_by(name: "USERNAME")

    patch "/api/container_images/#{@image.id}/env_params/#{setting.id}", params: {
      env_param: {
        param_type: "static",
        static_value: "kris"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "kris", data['env_param']['static_value']

  end

  test "delete environmental parameter" do

    setting = @image.env_params.find_by(name: "USERNAME")

    delete "/api/container_images/#{@image.id}/env_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end
