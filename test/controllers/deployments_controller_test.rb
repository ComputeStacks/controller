require 'test_helper'

class DeploymentsControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test 'can list projects' do
    sign_in users(:admin)
    get '/deployments'
    assert_response :success
  end

  test 'can view project' do
    sign_in users(:admin)
    get "/deployments/#{deployments(:project_test).token}"

    assert_response :success

  end

  test 'can view collaborated project' do
    sign_in users(:user)

    get "/deployments/#{deployments(:project_test).token}"
    assert_response :redirect

    d = deployments(:project_test)

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/deployments/#{deployments(:project_test).token}"
    assert_response :redirect

    d.deployment_collaborators.first.update active: true

    get "/deployments/#{deployments(:project_test).token}"
    assert_response :success

    d.deployment_collaborators.delete_all

  end

end
