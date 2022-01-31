require 'test_helper'

class Api::Admin::ProjectsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test 'can change project owner' do
    deployment = deployments(:project_test)
    original_user = deployment.user

    ##
    # Set to new user
    new_user = {
      project: {
        user_id: users(:user).id
      }
    }

    # Should initially fail because of the custom image in use
    put "/api/admin/projects/#{deployment.id}", params: new_user, as: :json, headers: @basic_auth_headers
    assert_response 422

    # Now add the user as a collaborator on the custom wordpress image
    image = container_images(:custom)
    image.container_image_collaborators.create! current_user: users(:admin), collaborator: users(:user)
    image.container_image_collaborators.first.update active: true

    put "/api/admin/projects/#{deployment.id}", params: new_user, as: :json, headers: @basic_auth_headers
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal users(:user).id, data['project']['user']['id']

    ##
    # Reset to previous user for other tests
    old_user = {
      project: {
        user_id: original_user.id
      }
    }
    put "/api/admin/projects/#{deployment.id}", params: old_user, as: :json, headers: @basic_auth_headers
    assert_response :success
    data2 = JSON.parse(response.body)
    assert_equal original_user.id, data2['project']['user']['id']

    # cleanup
    image.container_image_collaborators
  end

end
