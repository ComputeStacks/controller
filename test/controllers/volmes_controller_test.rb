require 'test_helper'

class VolumesControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test 'collaborats can view volume' do

    sign_in users(:user)

    d = deployments :project_test

    get "/volumes/#{d.volumes.first.id}"

    assert_response :redirect

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/volumes/#{d.volumes.first.id}"
    assert_response :redirect

    d.deployment_collaborators.first.update active: true

    get "/volumes/#{d.volumes.first.id}"
    assert_response :success

    d.deployment_collaborators.delete_all

  end

end
