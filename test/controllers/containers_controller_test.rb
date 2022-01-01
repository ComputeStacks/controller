require 'test_helper'

class ContainerControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test 'can view container' do
    sign_in users(:admin)
    get "/containers/#{deployment_containers(:wordpress_1).id}"

    assert_response :success

  end

  test 'collaborators can view container' do
    sign_in users(:user)
    get "/containers/#{deployment_containers(:wordpress_1).id}"
    assert_response :redirect

    d = deployment_containers(:wordpress_1).deployment
    d.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/containers/#{deployment_containers(:wordpress_1).id}"
    assert_response :redirect

    d.deployment_collaborators.first.update active: true

    get "/containers/#{deployment_containers(:wordpress_1).id}"
    assert_response :success

    d.deployment_collaborators.delete_all

  end

end
