require 'test_helper'

class Api::ContainerImages::IngressParamsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase
  
  setup do
    @image = ContainerImage.find_by(name: 'custom')
  end

  test "list port params" do

    get "/api/container_images/#{@image.id}/ingress_params", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal @image.ingress_params.count, data['ingress_params'].count

  end

  test "view port parameter" do

    setting = @image.ingress_params.first

    get "/api/container_images/#{@image.id}/ingress_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal setting.port, data['ingress_param']['port']
    assert_equal setting.proto, data['ingress_param']['proto']

  end

  test "create port parameter" do

    post "/api/container_images/#{@image.id}/ingress_params", params: {
      ingress_param: {
        port: 8000,
        proto: 'tcp',
        external_access: true
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal 8000, data['ingress_param']['port']    

  end

  test "update port parameter" do

    setting = @image.ingress_params.first

    patch "/api/container_images/#{@image.id}/ingress_params/#{setting.id}", params: {
      ingress_param: {
        port: 8501,
        proto: 'tcp',
        external_access: true
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal 8501, data['ingress_param']['port']

  end

  test "delete port parameter" do

    setting = @image.ingress_params.first

    delete "/api/container_images/#{@image.id}/ingress_params/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end
