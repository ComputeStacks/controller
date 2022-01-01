require 'test_helper'

class Api::Stacks::LoadBalancersControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  test "authenticate and retrieve load balancer configuration" do

    node = Deployment::ContainerService.web_only.first.nodes.first
    assert_not_nil node

    get "/api/stacks/load_balancers", headers: {
      'Accept' => 'text/plain',
      'Authorization' => "Bearer #{ClusterAuthService.new(node).auth_token}"
    }

    assert_response :success

    # Ensure all services are present
    node.container_services.web_only.each do |service|
      service.ingress_rules.each do |ingress|
        rule = Digest::MD5.hexdigest("#{service.name}#{ingress.id}")
        assert_match /backend #{rule}/, response.body
        assert_match /use_backend #{rule}/, response.body
        service.containers.each do |container|
          assert_match /server #{container.name} #{container.ip_address.ipaddr}:#{ingress.port}/, response.body
        end
      end
    end

  end

end
