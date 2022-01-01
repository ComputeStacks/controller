require 'test_helper'

class ContainerRegistry::RegistryConnectControllerTest < ActionDispatch::IntegrationTest
  
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test "can view registry password" do

    registry = ContainerRegistry.first

    assert_not_nil registry

    Rails.logger.warn registry.to_json

    get "/container_registry/#{registry.id}/registry_connect/password", xhr: true

    assert_response :success

    assert_equal response.body, registry.registry_password

  end

end
