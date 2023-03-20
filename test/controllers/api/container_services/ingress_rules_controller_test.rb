require 'test_helper'

class Api::ContainerServices::IngressRulesControllerTest < ActionDispatch::IntegrationTest

  include ApiTestControllerBase

  setup do
    @service = deployment_container_services :wordpress
  end

  test "list ingress rules" do

    get "/api/container_services/#{@service.id}/ingress_rules", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    puts data['ingress_rules']

    assert_equal @service.ingress_rules.count, data['ingress_rules'].count

  end

  test "view ingress rule" do

    setting = @service.ingress_rules.first

    get "/api/networks/ingress_rules/#{setting.id}", as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    assert_equal setting.port, data['ingress_rule']['port']
    assert_equal setting.proto, data['ingress_rule']['proto']

  end

  test "update port parameter" do

    setting = @service.ingress_rules.first

    patch "/api/networks/ingress_rules/#{setting.id}", params: {
      ingress_rule: {
        port: 8501,
        tcp_proxy_opt: 'send-proxy-v2'
      }
    }, as: :json, headers: @basic_auth_headers

    assert_response :success

    data = JSON.parse(response.body)

    # the port should not be changed!
    assert_equal 8501, data['ingress_rule']['port']
    assert_equal 'send-proxy-v2', data['ingress_rule']['tcp_proxy_opt']

  end


end
