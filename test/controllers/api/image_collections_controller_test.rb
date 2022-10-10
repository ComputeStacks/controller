require 'test_helper'

class Api::ImageCollectionsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list image collections' do

    get "/api/image_collections", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute data['image_collections'].empty?

  end
end
