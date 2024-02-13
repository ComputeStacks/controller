require 'test_helper'

class Api::Projects::VolumesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list volumes' do
    project = deployments(:project_test)
    get "/api/projects/#{project.id}/volumes", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data['volumes']

    # Ensure we have ALL of the volumes we expect, and nothing more.
    assert_empty project.volumes.pluck(:id) - data['volumes'].collect { |i| i['id']}
  end

  test 'can view a volume' do

    project = deployments(:project_test)
    v = project.volumes.first
    get "/api/projects/#{project.id}/volumes/#{v.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal v.id, data['volume']['id']
  end
end
