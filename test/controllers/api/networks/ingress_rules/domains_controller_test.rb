require 'test_helper'

class Api::Networks::IngressRules::DomainsControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  setup do
    @service = deployment_container_services :wordpress
  end

  test "list all domains" do

    ingress = @service.ingress_rules.find_by port: 80

    assert_not_nil ingress

    get "/api/networks/ingress_rules/#{ingress.id}/domains", as: :json, headers: @basic_auth_headers

    data = JSON.parse(response.body)

    assert_response :success
    assert_not_empty data["domains"]

  end

end
