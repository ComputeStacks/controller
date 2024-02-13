require 'test_helper'

class Api::ContainerServices::VolumesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list volumes' do
    s = deployment_container_services(:wordpress)
    get "/api/container_services/#{s.id}/volumes", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['volumes']

    # Ensure we have ALL of the volumes we expect, and nothing more.
    assert_empty s.volumes.pluck(:id) - data['volumes'].collect { |i| i['id']}
  end

  test 'can view a volume' do

    s = deployment_container_services(:wordpress)
    v = s.volumes.first
    get "/api/container_services/#{s.id}/volumes/#{v.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal v.id, data['volume']['id']
  end
end
