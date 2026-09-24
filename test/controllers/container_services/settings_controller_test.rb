require "test_helper"
class ContainerServices::SettingsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  test "can create setting" do
    sign_in users(:admin)
    service = Deployment::ContainerService.web_only.first

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: "test",
        value: "foobar"
      }
    }

    assert_response :redirect

    refute service.setting_params.find_by(name: "test").nil?
  end

  test "creating a static setting stores the value verbatim" do
    sign_in users(:admin)
    service = deployment_container_services :wordpress

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: "static_setting",
        param_type: "static",
        value: "plain text"
      }
    }

    assert_response :redirect

    setting = service.setting_params.find_by(name: "static_setting")
    refute setting.nil?
    assert_equal "static", setting.param_type
    assert_equal "plain text", setting.value
    assert_equal "plain text", setting.decrypted_value
  end

  test "creating a password setting stores ciphertext" do
    sign_in users(:admin)
    service = deployment_container_services :wordpress

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: "secret_setting",
        param_type: "password",
        value: "sup3rs3cret"
      }
    }

    assert_response :redirect

    setting = service.setting_params.find_by(name: "secret_setting")
    refute setting.nil?
    assert_equal "password", setting.param_type
    refute_equal "sup3rs3cret", setting.value
    assert_equal "sup3rs3cret", setting.decrypted_value
  end

  test "creating a password setting with a blank value is rejected" do
    sign_in users(:admin)
    service = deployment_container_services :wordpress

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: "blank_secret",
        param_type: "password",
        value: ""
      }
    }

    assert_response :success
    assert service.setting_params.find_by(name: "blank_secret").nil?
  end

  test "creating a setting with an invalid param_type is rejected" do
    sign_in users(:admin)
    service = deployment_container_services :wordpress

    post "/container_services/#{service.id}/settings", params: {
      container_service_setting_config: {
        name: "bogus_setting",
        param_type: "bogus",
        value: "foo"
      }
    }

    assert_response :success
    assert service.setting_params.find_by(name: "bogus_setting").nil?
  end

  test "updating a password setting with a new value re-encrypts it" do
    sign_in users(:admin)
    setting = container_service_setting_configs :wordpress_0
    service = setting.container_service
    original = setting.value

    put "/container_services/#{service.id}/settings/#{setting.id}", params: {
      container_service_setting_config: {
        label: setting.label,
        value: "brandnewpassword"
      }
    }

    assert_response :redirect

    setting.reload
    refute_equal original, setting.value
    refute_equal "brandnewpassword", setting.value
    assert_equal "brandnewpassword", setting.decrypted_value
  end

  test "updating a password setting with a blank value leaves it untouched" do
    sign_in users(:admin)
    setting = container_service_setting_configs :wordpress_0
    service = setting.container_service
    original = setting.value
    original_decrypted = setting.decrypted_value

    put "/container_services/#{service.id}/settings/#{setting.id}", params: {
      container_service_setting_config: {
        label: "Renamed Password",
        value: ""
      }
    }

    assert_response :redirect

    setting.reload
    assert_equal "Renamed Password", setting.label
    assert_equal original, setting.value
    assert_equal original_decrypted, setting.decrypted_value
  end

  test "updating a static setting with a blank value clears it" do
    sign_in users(:admin)
    setting = container_service_setting_configs :wordpress_2
    service = setting.container_service

    assert_equal "static", setting.param_type
    refute setting.value.blank?

    put "/container_services/#{service.id}/settings/#{setting.id}", params: {
      container_service_setting_config: {
        label: setting.label,
        value: ""
      }
    }

    assert_response :redirect

    setting.reload
    assert setting.value.blank?
  end

  test "edit form for a password setting renders an empty submittable value field" do
    sign_in users(:admin)
    setting = container_service_setting_configs :wordpress_0
    service = setting.container_service

    get "/container_services/#{service.id}/settings/#{setting.id}/edit"

    assert_response :success
    assert_select "input[name='container_service_setting_config[value]']" do |elements|
      assert_equal 1, elements.count
      assert elements.first["value"].blank?
      assert elements.first["disabled"].nil?
    end
  end

  test "param_type cannot be changed on update" do
    sign_in users(:admin)
    setting = container_service_setting_configs :wordpress_2
    service = setting.container_service

    put "/container_services/#{service.id}/settings/#{setting.id}", params: {
      container_service_setting_config: {
        label: setting.label,
        param_type: "password",
        value: "still plain"
      }
    }

    assert_response :redirect

    setting.reload
    assert_equal "static", setting.param_type
    assert_equal "still plain", setting.value
  end

  test "collaborators can view setting" do
    sign_in users(:user)
    setting = container_service_setting_configs :wordpress_0
    service = setting.container_service

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: {"Accept" => "application/json"}
    assert_response 401

    service.deployment.deployment_collaborators.create! current_user: users(:admin), collaborator: users(:user)

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: {"Accept" => "application/json"}
    assert_response 401

    service.deployment.deployment_collaborators.first.update active: true

    get "/container_services/#{service.id}/settings/#{setting.id}", as: :json, xhr: true, headers: {"Accept" => "application/json"}
    assert_response :success

    service.deployment.deployment_collaborators.delete_all
  end
end
