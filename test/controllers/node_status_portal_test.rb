require "test_helper"

# The customer portal's node status: the banner on the project and service pages, the
# label on the container page and project list, and the power action flash.
class NodeStatusPortalTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_holds: {}, disconnected: false,
      disconnected_at: nil, customer_notice: nil)
    @project_path = "/deployments/#{deployments(:project_test).token}"
    @service_path = "/container_services/#{deployment_container_services(:wordpress).id}"
  end

  def in_maintenance!(notice: "Kernel upgrade <b>tonight</b>")
    @node.update_columns(maintenance_requested: true, maintenance_updated: Time.now, customer_notice: notice)
  end

  def offline!(notice: "Investigating a network outage")
    @node.update_columns(disconnected: true, disconnected_at: 10.minutes.ago, customer_notice: notice)
  end

  test "no banner on the project and service pages while the node is online" do
    [@project_path, @service_path].each do |path|
      get path
      assert_response :success
      assert_no_match "node-status-banner", response.body, path
    end
  end

  test "maintenance banner with the escaped customer message on the project and service pages" do
    in_maintenance!

    [@project_path, @service_path].each do |path|
      get path
      assert_response :success
      assert_select ".node-status-banner.alert-warning", 1, path
      assert_match I18n.t("node_status.headline.maintenance"), response.body
      assert_match I18n.t("node_status.operations.power_deferred"), response.body
      assert_match "Backups, restores, downloads", response.body
      assert_match "Kernel upgrade &lt;b&gt;tonight&lt;/b&gt;", response.body
      assert_no_match "<b>tonight</b>", response.body
    end
  end

  test "offline banner on the project and service pages" do
    offline!

    [@project_path, @service_path].each do |path|
      get path
      assert_response :success
      assert_select ".node-status-banner.alert-danger", 1, path
      assert_match I18n.t("node_status.headline.offline"), response.body
      assert_match I18n.t("node_status.operations.power_refused"), response.body
      assert_match "Investigating a network outage", response.body
    end
  end

  test "the internal maintenance reason is never shown" do
    in_maintenance!
    @node.update_columns(maintenance_reason: "secret-internal-reason")

    get @project_path
    assert_no_match "secret-internal-reason", response.body
  end

  test "container page labels the node when it is not online" do
    container = deployment_containers(:wordpress_1)
    get "/containers/#{container.id}"
    assert_response :success
    assert_select "span.label-warning", text: I18n.t("node_status.label.maintenance"), count: 0

    in_maintenance!
    get "/containers/#{container.id}"
    assert_response :success
    assert_select "span.label-warning", text: I18n.t("node_status.label.maintenance")
  end

  test "project list labels projects that are not online" do
    get "/deployments", xhr: true
    assert_response :success
    assert_select "span.label-danger", text: I18n.t("node_status.label.offline"), count: 0

    offline!
    get "/deployments", xhr: true
    assert_response :success
    assert_select "span.label-danger", text: I18n.t("node_status.label.offline")
  end

  test "a power action during maintenance says it will run when maintenance ends" do
    in_maintenance!
    container = deployment_containers(:wordpress_1)

    patch "/containers/#{container.id}/power_management/restart"

    assert_redirected_to "/container_services/#{container.service.id}"
    assert_equal I18n.t("node_status.power.deferred"), flash[:notice]
  end

  test "a power action on an offline node is refused with an error" do
    offline!
    container = deployment_containers(:wordpress_1)

    patch "/containers/#{container.id}/power_management/restart"

    assert_redirected_to "/container_services/#{container.service.id}"
    assert_equal I18n.t("node_status.power.refused_offline"), flash[:alert]
  end
end
