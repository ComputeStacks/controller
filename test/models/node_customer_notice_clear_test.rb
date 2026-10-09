require "test_helper"

##
# The customer notice is cleared when the node returns to fully online, and never while
# it is still disconnected or in maintenance.
class NodeCustomerNoticeClearTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(disconnected: true, maintenance_requested: false, maintenance_holds: {},
      maintenance_gen: 41, maintenance_seq: 97, customer_notice: "Hardware fault")
    @node.reload
    clear_claims!
  end

  teardown { clear_claims! }

  def clear_claims!
    Sidekiq.redis do |c|
      [true, false].each { |v| c.call("DEL", "node_maintenance_transition:#{@node.id}:#{v}:97:41") }
    end
  end

  test "mark_online! clears the notice" do
    @node.mark_online!
    assert_nil @node.customer_notice
    assert_nil @node.reload.customer_notice
  end

  test "mark_online! keeps the notice while the node is in maintenance" do
    @node.update_columns(maintenance_requested: true)
    @node.reload.mark_online!
    assert_equal "Hardware fault", @node.reload.customer_notice
  end

  test "end of maintenance clears the notice" do
    @node.update_columns(disconnected: false)
    @node.reload
    Nodes::MaintenanceTransitions.handle(@node, was: true, now: false)
    assert_nil @node.reload.customer_notice
  end

  test "end of maintenance keeps the notice while the node is still disconnected" do
    Nodes::MaintenanceTransitions.handle(@node, was: true, now: false)
    assert_equal "Hardware fault", @node.reload.customer_notice
  end

  test "entering maintenance does not clear" do
    @node.update_columns(disconnected: false, maintenance_requested: true)
    Nodes::MaintenanceTransitions.handle(@node.reload, was: false, now: true)
    assert_equal "Hardware fault", @node.reload.customer_notice
  end

  test "the helper re-checks the row, not the in-memory node" do
    @node.disconnected = false # stale in memory; the row is still disconnected
    refute @node.clear_customer_notice_if_online!
    assert_equal "Hardware fault", @node.reload.customer_notice
  end
end
