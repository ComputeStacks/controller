require "test_helper"
require "minitest/mock"

class Api::Projects::ContainersControllerTest < ActionDispatch::IntegrationTest
  include ApiTestControllerBase

  test "pre-resolves on_latest_image within the request budget" do
    project = Deployment::Container.first.deployment
    resolved = nil
    Deployment::Container.stub(:resolve_latest_images, ->(cs) { resolved = cs; cs.each { |c| c.latest_image_result = false } }) do
      get "/api/projects/#{project.id}/containers", as: :json, headers: @basic_auth_headers
    end

    assert_response :success
    refute_empty resolved
    assert(JSON.parse(response.body)["containers"].none? { |c| c["on_latest_image"] })
  end
end
