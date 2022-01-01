require 'test_helper'

class Api::ContainerImages::ImageRelationshipsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  setup do
    @image = ContainerImage.find_by(name: 'custom')
  end
  
  test "list image relationships" do

    get "/api/container_images/#{@image.id}/image_relationships", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal @image.dependency_parents.count, data['image_relationships'].count

  end

  test "delete image relationship" do

    rel = @image.dependency_parents.first

    delete "/api/container_images/#{@image.id}/image_relationships/#{rel.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

  test "create image relationship" do

    image = ContainerImage.find_by(name: "wordpress")

    post "/api/container_images/#{@image.id}/image_relationships", params: {
      image_relationship: {
        requires_container_id: image.id
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end