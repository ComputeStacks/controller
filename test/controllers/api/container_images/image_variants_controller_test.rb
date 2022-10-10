require 'test_helper'

class Api::ContainerImages::ImageVariantsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can CRUD image variants' do

    image = container_images(:nginx)

    post "/api/container_images/#{image.id}/image_variants", params: {
      image_variant: {
        label: "stable",
        version: 1,
        registry_image_tag: "stable"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse response.body

    assert_equal "stable", data['image_variant']['label']

    id = data['image_variant']['id']

    patch "/api/container_images/#{image.id}/image_variants/#{id}", params: {
      image_variant: {
        label: "stable new"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse response.body

    assert_equal "stable new", data['image_variant']['label']

    delete "/api/container_images/#{image.id}/image_variants/#{id}", as: :json, headers: @basic_auth_headers

  end

end
