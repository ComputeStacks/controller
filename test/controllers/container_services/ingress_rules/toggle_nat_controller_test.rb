require 'test_helper'

class ContainerServices::IngressRules::ToggleNatControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test 'can toggle nat' do

    service = Deployment::ContainerService.where(container_images: { name: 'mariadb-105' }).joins(:container_image).first

    ingress = service.ingress_rules.first # mysql only has 1
    original_nat_port = ingress.port_nat
    original_lb_access = ingress.external_access

    post "/container_services/#{service.id}/ingress/#{ingress.id}/toggle_nat"

    assert_response :redirect
    ingress.reload

    # Both the LB type and port_nat should be changed
    assert_not_equal original_nat_port, ingress.port_nat
    assert_not_equal original_lb_access, ingress.external_access

  end

end
