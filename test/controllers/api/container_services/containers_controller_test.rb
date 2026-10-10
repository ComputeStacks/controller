require "test_helper"
require "minitest/mock"

class Api::ContainerServices::ContainersControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  test "can list containers" do
    get "/api/container_services/#{deployment_container_services(:wordpress).id}/containers", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    refute_empty data["containers"]

    assert data["containers"].first["on_latest_image"]
  end

  test "pre-resolves on_latest_image within the request budget" do
    service = deployment_container_services(:wordpress)
    resolved = nil
    Deployment::Container.stub(:resolve_latest_images, ->(cs) { resolved = cs; cs.each { |c| c.latest_image_result = false } }) do
      get "/api/container_services/#{service.id}/containers", as: :json, headers: @basic_auth_headers
    end

    assert_response :success
    assert_equal service.containers.pluck(:id).sort, resolved.map(&:id).sort
    assert(JSON.parse(response.body)["containers"].none? { |c| c["on_latest_image"] })
  end
end
