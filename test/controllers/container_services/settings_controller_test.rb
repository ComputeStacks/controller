require 'test_helper'
class ContainerServices::SettingsControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test "can create setting" do
    sign_in users(:admin)
    service = Deployment::ContainerService.web_only.first

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: 'test',
        value: 'foobar'
      }
    }

    assert_response :redirect

    refute service.setting_params.find_by(name: 'test').nil?

  end

  test 'collaborators can view setting' do

    sign_in users(:user)
    setting = container_service_setting_configs :wordpress_0
    service = setting.container_service

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }
    assert_response 401

    service.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }
    assert_response 401

    service.deployment.deployment_collaborators.first.update active: true

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }
    assert_response :success

    service.deployment.deployment_collaborators.delete_all

  end


end
