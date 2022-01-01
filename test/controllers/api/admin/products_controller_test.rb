require 'test_helper'

class Api::Admin::ProductsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list all' do

    get "/api/admin/products", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)
    assert_not_empty data['products']

  end

  test 'can load product' do

    get "/api/admin/products/#{products(:containerl).id}", as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse(response.body)

    assert_equal 'default', data['product']['group']

  end

  test 'can create product' do

    post "/api/admin/products", params: {
      product: {
        label: "foobar",
        package_attributes: {
          cpu: 2.5,
          memory: 1536,
          memory_swap: 1536,
          memory_swappiness: 15,
          bandwidth: 2000,
          storage: 18,
          local_disk: 9,
          backup: 35
        }
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success
    data = JSON.parse response.body

    assert_equal 'foobar', data['product']['label']
    assert_equal "2.5", data['product']['package']['cpu']
    assert_equal 1536, data['product']['package']['memory']
    assert_equal 1536, data['product']['package']['memory_swap']
    assert_equal 15, data['product']['package']['memory_swappiness']
    assert_equal 2000, data['product']['package']['bandwidth']
    assert_equal 18, data['product']['package']['storage']
    assert_equal 9, data['product']['package']['local_disk']
    assert_equal 35, data['product']['package']['backup']

  end

end
