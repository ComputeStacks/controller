require 'test_helper'

class Api::Admin::Locations::AllocatedResourcesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can get resources' do

    get "/api/admin/locations/#{locations(:testlocation).id}/allocated_resources", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)
    assert_not_empty data['availability_zones']

    assert_equal Deployment::Sftp.count, data['total']['sftp_containers']
    assert_equal Deployment::Sftp.count, data['availability_zones'][0]['allocated']['sftp_containers']

  end
end
