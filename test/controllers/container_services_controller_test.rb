require "test_helper"

class ContainerServicesControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  # setup do
  #   sign_in users(:admin)
  # end

  test "can view container service" do
    sign_in users(:admin)
    get "/container_services/#{deployment_container_services(:wordpress).id}"

    assert_response :success
  end

  test "cant view unauthorized service" do
    sign_in users(:user)
    get "/container_services/#{deployment_container_services(:wordpress).id}"
    assert_response :redirect
  end

  test "can view collaborated service" do
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

  test "can set shm size in MB from the edit form" do
    sign_in users(:admin)
    service = deployment_container_services(:wordpress) # memory: 1024 MB

    patch "/container_services/#{service.id}",
      params: {deployment_container_service: {shm_size_mb: 256}}

    assert_response :redirect
    assert_equal 256 * 1_048_576, service.reload.shm_size
  end

  test "shm size over the memory limit is rejected on the edit form" do
    sign_in users(:admin)
    service = deployment_container_services(:wordpress) # memory: 1024 MB

    patch "/container_services/#{service.id}",
      params: {deployment_container_service: {shm_size_mb: service.memory + 1}}

    assert_response :success # re-renders edit with the error
    assert_equal 0, service.reload.shm_size
  end
end
