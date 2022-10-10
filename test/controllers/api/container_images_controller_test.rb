require 'test_helper'

class Api::ContainerImagesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "list container images" do
    get "/api/container_images",
      as: :json,
      headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal data['container_images'].count, ContainerImage.count
    assert_includes data['container_images'].map { |i| i['label'].downcase }, 'wordpress'
  end

  test "view a container image" do

    image = ContainerImage.first

    get "/api/container_images/#{image.id}", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)

    assert_equal image.id, data['container_image']['id']

  end

  test "update an image" do

    image = ContainerImage.find_by(name: 'custom')

    assert_not_nil image

    patch "/api/container_images/#{image.id}", params: {
      container_image: {
        label: "Wordpress Update"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)

    assert_equal "Wordpress Update", data['container_image']['label']

  end

  test "create an image" do

    provider = ContainerImageProvider.first

    assert_not_nil provider

    post "/api/container_images", params: {
      container_image: {
        active: true,
        can_scale: true,
        container_image_provider_id: provider.id,
        description: "Test Image",
        label: "My Image",
        min_cpu: 1,
        min_memory: 256,
        registry_image_path: "cmptstks/nginx",
        registry_image_tag: "latest",
        role: "nginx",
        category: "web",
        ingress_params_attributes: [{
          port: 80,
          proto: 'http',
          external_access: true
        }],
        setting_params_attributes: [{
          name: "username",
          label: "Username",
          param_type: "static",
          value: "admin"
        }],
        env_params_attributes: [{
          name: "USERNAME",
          param_type: "variable",
          env_value: "build.settings.username"
        }],
        volumes_attributes: [{
          label: "webdir",
          mount_path: "/mnt/test"
        }]
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal "My Image", data['container_image']['label']

  end

  test "delete a container image" do

    image = ContainerImage.find_by(name: 'deleteme')

    delete "/api/container_images/#{image.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    assert_nil ContainerImage.find_by(name: 'deleteme')

  end

end
