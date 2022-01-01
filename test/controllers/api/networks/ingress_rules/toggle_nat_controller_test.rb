require 'test_helper'

class Api::Networks::IngressRules::ToggleNatControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  setup do
    @service = Deployment::ContainerService.find_by(name: 'fervent-goodall195')
  end

  test "toggle ingress nat port" do

    ingress = @service.ingress_rules.find_by(port: 3306)

    assert_not_nil ingress

    post "/api/networks/ingress_rules/#{ingress.id}/toggle_nat", as: :json, headers: @basic_auth_headers

    assert_response :success

  end

end
