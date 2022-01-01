require 'test_helper'

class Api::ContainerImages::VolumeParamsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase
  
  setup do
    @image = ContainerImage.find_by(name: 'custom')
  end

  test "list volume parameters" do

    get "/api/container_images/#{@image.id}/volume_params", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal @image.volumes.count, data['volume_params'].count

  end

  test "view volume parameter" do

    vol = @image.volumes.first

    get "/api/container_images/#{@image.id}/volume_params/#{vol.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal vol.label, data['volume_param']['label']

  end

  test "create volume parameter" do

    post "/api/container_images/#{@image.id}/volume_params", params: {
      volume_param: {
        label: "webdev",
        mount_path: "/mnt/test",
        enable_sftp: true,
        borg_enabled: true,
        borg_freq: '@daily',
        borg_strategy: 'file'
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "webdev", data['volume_param']['label']    

  end

  test "update volume parameter" do

    vol = @image.volumes.first

    patch "/api/container_images/#{@image.id}/volume_params/#{vol.id}", params: {
      volume_param: {
        label: "testvol"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "testvol", data['volume_param']['label']

  end

  test "delete volume parameter" do

    vol = @image.volumes.first

    delete "/api/container_images/#{@image.id}/volume_params/#{vol.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end
