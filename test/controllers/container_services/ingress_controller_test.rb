require 'test_helper'

class ContainerServices::IngressControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test 'collaborators can list ingress rules (xhr)' do

    sign_in users(:user)
    service = deployment_container_services :wordpress

    get "/container_services/#{service.id}/ingress", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }

    assert_response 401

    service.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_services/#{service.id}/ingress", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }

    assert_response 401

    service.deployment.deployment_collaborators.first.update active: true

    get "/container_services/#{service.id}/ingress", as: :json, xhr: true, headers: { 'Accept' => 'application/json' }

    assert_not_empty JSON.parse(response.body)

    service.deployment.deployment_collaborators.delete_all

  end

  test 'can list ingress rules (xhr)' do
    sign_in users(:admin)
    service = Deployment::ContainerService.web_only.first

    get "/container_services/#{service.id}/ingress", as: :json, xhr: true, headers: {
      'Accept' => 'application/json'
    }

    assert_response :success

    assert_not_empty JSON.parse(response.body)

  end

  test 'can manage additional ingress rules' do
    sign_in users(:admin)
    service = Deployment::ContainerService.web_only.first

    post "/container_services/#{service.id}/ingress", params: {
      network_ingress_rule: {
        proto: 'tcp',
        port: 2543,
        external_access: true,
        tcp_lb: false
      }
    }

    assert_response :redirect
    new_rule = service.ingress_rules.find_by(port: 2543)
    refute new_rule.nil?

    delete "/container_services/#{service.id}/ingress/#{new_rule.id}"

    assert_response :redirect

    new_rule = service.ingress_rules.find_by(port: 2543)

    assert new_rule.nil?


  end

end
