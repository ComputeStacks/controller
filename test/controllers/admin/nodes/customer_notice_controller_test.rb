require "test_helper"

class Admin::Nodes::CustomerNoticeControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_holds: {}, disconnected: false,
      customer_notice: nil)
    @path = "/admin/nodes/#{@node.id}/customer_notice"
    @edit = "/admin/nodes/#{@node.id}/edit"
  end

  test "sets the notice while the node is in maintenance, audited" do
    @node.update_columns(maintenance_requested: true)

    assert_difference -> { Audit.count }, 1 do
      patch @path, params: {customer_notice: "Back by 14:00 UTC"}
    end

    assert_redirected_to @edit
    assert_match "set", flash[:notice]
    assert_equal "Back by 14:00 UTC", @node.reload.customer_notice
  end

  test "sets the notice while the node is offline" do
    @node.update_columns(disconnected: true, disconnected_at: Time.now)

    patch @path, params: {customer_notice: "Network outage"}

    assert_redirected_to @edit
    assert_equal "Network outage", @node.reload.customer_notice
  end

  test "refuses to set a notice while the node is online" do
    patch @path, params: {customer_notice: "Hello"}

    assert_redirected_to @edit
    assert_match "only be set while the node is in maintenance or offline", flash[:alert]
    assert_nil @node.reload.customer_notice
  end

  test "clears the notice" do
    @node.update_columns(maintenance_requested: true, customer_notice: "Old")

    delete @path

    assert_redirected_to @edit
    assert_match "cleared", flash[:notice]
    assert_nil @node.reload.customer_notice
  end

  test "the edit page has the customer notice form" do
    @node.update_columns(maintenance_requested: true, customer_notice: "Kernel upgrade")

    get @edit

    assert_response :success
    assert_select "#node-customer-notice textarea[name=customer_notice]", text: "Kernel upgrade"
    assert_match "/api/locations", response.body
  end
end
