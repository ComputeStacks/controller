require 'test_helper'

class Api::ContainersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can view a container' do
    VCR.use_cassette('controllers/api/containers/show') do
      c = Deployment::Container.first
      get "/api/containers/#{c.id}", as: :json, headers: @basic_auth_headers

      assert_response :success
    end
  end
end
