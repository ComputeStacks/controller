require 'test_helper'

class ContainerImageControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test "create container image with custom auth" do
    sign_in users(:admin)
    reg_url = 'cr.cmptstks.com'
    reg_pw = 'WYF6A6jy2vxZjALQbFos'
    reg_user = 'gitlab+deploy-token-2'

    post "/container_images", params: {
      container_image: {
        label: 'redis-dev',
        active: true,
        role: 'redis',
        role_class: 'cache',
        registry_image_path: 'cs/portal/redis',
        registry_custom: reg_url,
        registry_image_tag: 'alpine',
        registry_auth: true,
        registry_username: reg_user,
        registry_password: reg_pw
      }
    }

    assert_response :redirect

    # find created image and ensure password was saved
    image = ContainerImage.find_by(registry_username: 'gitlab+deploy-token-2')
    assert_equal reg_pw, image.registry_password

    # Verify image auth is correct
    auth = image.image_auth

    assert_equal reg_user, auth['username']
    assert_equal reg_pw, auth['password']

  end

  test 'can view collaborated image' do
    sign_in users(:user)

    image = container_images(:custom)

    get "/container_images/#{image.id}"
    assert_response :redirect

    image.container_image_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_images/#{image.id}"
    assert_response :redirect

    image.container_image_collaborators.first.update active: true

    get "/container_images/#{image.id}"
    assert_response :success

    image.container_image_collaborators.delete_all

  end

  test 'can view project image collaboration' do
    sign_in users(:user)

    d = deployments :project_test
    image = container_images :custom

    get "/container_images/#{image.id}"
    assert_response :redirect

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_images/#{image.id}"
    assert_response :redirect

    d.deployment_collaborators.first.update active: true

    get "/container_images/#{image.id}"
    assert_response :success

    d.deployment_collaborators.delete_all

  end

end
