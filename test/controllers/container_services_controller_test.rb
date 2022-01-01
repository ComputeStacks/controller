require 'test_helper'

class ContainerServicesControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  # setup do
  #   sign_in users(:admin)
  # end

  test 'can view container service' do
    sign_in users(:admin)
    get "/container_services/#{deployment_container_services(:wordpress).id}"

    assert_response :success

  end

  test 'cant view unauthorized service' do

    sign_in users(:user)
    get "/container_services/#{deployment_container_services(:wordpress).id}"
    assert_response :redirect

  end

  test 'can view collaborated service' do

    sign_in users(:user)

    d = deployment_container_services(:wordpress).deployment

    d.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_services/#{deployment_container_services(:wordpress).id}"
    assert_response :redirect

    d.deployment_collaborators.first.update active: true

    get "/container_services/#{deployment_container_services(:wordpress).id}"
    assert_response :success

    d.deployment_collaborators.delete_all


  end

end
