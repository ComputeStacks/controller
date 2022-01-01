require 'test_helper'

class Api::Cluster::AssetsControllerTest < ActionDispatch::IntegrationTest

  test "valid pma container requesting config" do
    get "/api/cluster/assets/pma", as: :json, headers: {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{ClusterAuthService.new(deployment_containers(:pma_1)).auth_token}"
    }
    assert_response :success
  end

  test 'invalid pma container requesting config' do
    get "/api/cluster/assets/pma", as: :json, headers: {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{ClusterAuthService.new(deployment_containers(:nginx_1)).auth_token}"
    }

    assert_response :missing
  end

end
