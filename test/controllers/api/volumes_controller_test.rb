require 'test_helper'

class Api::VolumesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can list volumes' do
    get "/api/volumes", as: :json, headers: @basic_auth_headers

    assert_response :success
  end
end
