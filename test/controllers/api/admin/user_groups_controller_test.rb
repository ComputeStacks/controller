require 'test_helper'

class Api::Admin::UserGroupsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list all user groups' do

    get "/api/admin/user_groups", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_not_empty data['user_groups']

  end

  test 'can load a single user group' do
    group = user_groups(:admin)
    get "/api/admin/user_groups/#{group.id}", as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)

    assert_equal group.id, data['user_group']['id']
  end

  test 'user group has correct regions' do
    group = user_groups(:admin)
    get "/api/admin/user_groups/#{group.id}", as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_empty data['user_group']['regions'].map { |i| i['id'] } - group.regions.pluck(:id)
  end

  test 'user group has correct locations' do
    group = user_groups(:admin)
    get "/api/admin/user_groups/#{group.id}", as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_empty data['user_group']['locations'].map { |i| i['id'] } - group.locations.pluck(:id)
  end

end
