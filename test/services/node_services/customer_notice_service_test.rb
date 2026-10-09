require "test_helper"

class NodeServices::CustomerNoticeServiceTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(disconnected: false, maintenance_requested: false, maintenance_holds: {}, customer_notice: nil)
    @node.reload
    @admin = users(:admin)
  end

  def service(notice)
    NodeServices::CustomerNoticeService.new(@node, notice: notice, actor: @admin, remote_ip: "10.1.2.3")
  end

  test "refuses to set a notice while the node is online" do
    s = service("Kernel upgrade")
    assert_no_difference -> { Audit.count } do
      refute s.perform
    end
    assert_match(/maintenance or offline/, s.errors.first)
    assert_nil @node.reload.customer_notice
  end

  test "sets a notice while in maintenance, audited with actor and IP" do
    @node.update_columns(maintenance_requested: true)
    assert_difference -> { Audit.count }, 1 do
      assert service("  Kernel upgrade ").perform
    end
    assert_equal "Kernel upgrade", @node.customer_notice
    audit = Audit.order(:id).last
    assert_equal @admin, audit.user
    assert_equal "10.1.2.3", audit.ip_addr.to_s
    assert_equal "Node", audit.rel_model
    assert_equal @node.id, audit.rel_id
    assert_equal({"customer_notice" => {"from" => nil, "to" => "Kernel upgrade"}}, audit.raw_data)
  end

  test "sets a notice while offline" do
    @node.update_columns(disconnected: true)
    assert service("Hardware fault").perform
    assert_equal "Hardware fault", @node.reload.customer_notice
  end

  test "blank clears, even while online" do
    @node.update_columns(customer_notice: "old")
    assert_difference -> { Audit.count }, 1 do
      assert service("  ").perform
    end
    assert_nil @node.reload.customer_notice
  end

  test "no change is not audited" do
    assert_no_difference -> { Audit.count } do
      assert service(nil).perform
    end
  end
end
