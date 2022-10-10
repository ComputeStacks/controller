require 'test_helper'

class Api::Admin::ImageCollectionsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can CRUD collection' do

    post "/api/admin/image_collections", params: {
      image_collection: {
        label: "foobar",
        active: true,
        sort: 5,
        container_image_ids: [ container_images(:nginx).id ]
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse response.body

    assert_equal 'foobar', data['image_collection']['label']
    assert_equal 5, data['image_collection']['sort']
    assert_equal container_images(:nginx).id, data['image_collection']['container_images'].first['id']

    id = data['image_collection']['id']

    patch "/api/admin/image_collections/#{id}", params: {
      image_collection: {
        label: "test"
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse response.body

    assert_equal "test", data['image_collection']['label']

    delete "/api/admin/image_collections/#{id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end
end
