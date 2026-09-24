require "test_helper"

class Api::ContainerServicesControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  test "can list container services" do
    get "/api/container_services", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data["container_services"]
  end

  test "can view container services" do
    get "/api/container_services/#{deployment_container_services(:wordpress).id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_nil data["container_service"]
  end

  test "can set shm_size (bytes) via update" do
    service = deployment_container_services(:wordpress) # memory: 1024 MB

    patch "/api/container_services/#{service.id}",
      params: {container_service: {shm_size: 256 * 1_048_576}},
      as: :json, headers: @basic_auth_headers

    assert_response :accepted
    data = JSON.parse(response.body)
    assert_equal 256 * 1_048_576, data["container_service"]["shm_size"]
    assert_equal 256 * 1_048_576, service.reload.shm_size
  end

  test "update rejects shm_size over the memory limit" do
    service = deployment_container_services(:wordpress) # memory: 1024 MB

    patch "/api/container_services/#{service.id}",
      params: {container_service: {shm_size: (service.memory + 1) * 1_048_576}},
      as: :json, headers: @basic_auth_headers

    assert_response :unprocessable_entity
    assert_equal 0, service.reload.shm_size
  end
end
