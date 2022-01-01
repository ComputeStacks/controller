require 'test_helper'

class Api::ContainerImages::SettingParamsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase
  
  setup do
    @image = ContainerImage.find_by(name: 'custom')
  end

  test "list setting parameters" do

    get "/api/container_images/#{@image.id}/setting_params", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal @image.setting_params.count, data['setting_params'].count

  end

  test "view setting parameter" do

    setting = @image.setting_params.first

    get "/api/container_images/#{@image.id}/setting_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal setting.value, data['setting_param']['value']

  end

  test "create setting parameter" do

    post "/api/container_images/#{@image.id}/setting_params", params: {
      setting_param: {
        name: "MY_SETTING",
        param_type: "static",
        value: "myval"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "myval", data['setting_param']['value']    

  end

  test "update setting parameter" do

    setting = @image.setting_params.find_by(name: "username")

    patch "/api/container_images/#{@image.id}/setting_params/#{setting.id}", params: {
      setting_param: {
        value: "kris"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "kris", data['setting_param']['value']

  end

  test "delete setting parameter" do

    setting = @image.setting_params.find_by(name: "username")

    delete "/api/container_images/#{@image.id}/setting_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end
