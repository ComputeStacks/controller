require "test_helper"
require "minitest/mock"

class Nodes::MaintenanceProjectionTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_gen: 5, maintenance_holds: {}, maintenance_seq: 0,
      agent_instance_id: nil, agent_maintenance_unsupported_at: nil)
    @node.reload
    @transitions = []
    @recorder = ->(node, was:, now:) { @transitions << [was, now] }
  end

  def payload(local: nil, controller: nil, instance: "inst-1")
    {"paused" => !(local || controller).nil?, "controller" => controller, "local" => local,
     "paused_since" => ((local || controller) ? 1_760_000_000 : nil), "skipped_backups" => 2,
     "sample" => nil, "instance_id" => instance, "controller_gen" => 5}
  end

  def apply(p, seq)
    Nodes::MaintenanceTransitions.stub(:handle, @recorder) do
      Nodes::MaintenanceProjection.apply_snapshot(@node, p, seq: seq)
    end
  end

  test "applies a snapshot at the given seq, without instance_id, and reports the transition" do
    assert apply(payload(local: {"since" => 1, "reason" => "docker", "by" => "root"}), 4)

    @node.reload
    assert_equal 4, @node.maintenance_seq
    assert_equal "docker", @node.maintenance_local_hold["reason"]
    refute @node.maintenance_holds.key?("instance_id")
    assert_equal 2, @node.maintenance_holds["skipped_backups"]
    assert @node.maintenance
    assert_equal [[false, true]], @transitions
  end

  test "a stale or equal seq does not regress the holds" do
    apply(payload(local: {"since" => 1, "reason" => "docker"}), 10)
    refute apply(payload, 9)
    refute apply(payload, 10)
    @node.reload
    assert_equal 10, @node.maintenance_seq
    assert @node.maintenance_local_hold
  end

  test "a nil stored instance_id is adopted silently" do
    assert_no_difference -> { SystemEvent.count } do
      apply(payload(instance: "first"), 1)
    end
    assert_equal "first", @node.reload.agent_instance_id
  end

  test "a changed instance_id resets the seq guard and alerts" do
    apply(payload(local: {"since" => 1, "reason" => "x"}, instance: "old"), 50)

    assert_difference -> { SystemEvent.where("message LIKE ?", "agent control.db replaced%").count }, 1 do
      assert apply(payload(instance: "new"), 3), "a lower seq from a new control.db applies"
    end
    @node.reload
    assert_equal "new", @node.agent_instance_id
    assert_equal 3, @node.maintenance_seq
    assert_nil @node.maintenance_local_hold
    assert_equal false, @node.maintenance
    assert_equal [[false, true], [true, false]], @transitions
  end

  test "a replaced control.db that has no entry yet (seq 0) still replaces stale holds" do
    apply(payload(local: {"since" => 1, "reason" => "x"}, instance: "old"), 50)
    assert apply(payload(instance: "new"), 0)
    assert_equal false, @node.reload.maintenance
  end

  test "a malformed payload or seq is ignored" do
    refute apply(nil, 1)
    refute apply(payload, nil)
    assert_equal 0, @node.reload.maintenance_seq
  end

  test "mark_unsupported! clears projected state, records when, and reports the transition" do
    apply(payload(local: {"since" => 1, "reason" => "x"}), 7)
    assert @node.reload.maintenance

    assert_difference -> { EventLog.where(locale: "node.maintenance.unsupported").count }, 1 do
      Nodes::MaintenanceTransitions.stub(:handle, @recorder) { Nodes::MaintenanceProjection.mark_unsupported!(@node) }
    end
    @node.reload
    assert_equal({}, @node.maintenance_holds)
    assert_equal 0, @node.maintenance_seq
    assert_nil @node.agent_instance_id
    assert @node.agent_maintenance_unsupported_at.present?
    assert_equal false, @node.maintenance, "effective maintenance falls back to requested alone"
    assert_equal [true, false], @transitions.last

    # The hourly re-probe of an old agent doesn't log again.
    assert_no_difference -> { EventLog.count } do
      Nodes::MaintenanceTransitions.stub(:handle, @recorder) { Nodes::MaintenanceProjection.mark_unsupported!(@node) }
    end
  end

  test "mark_unsupported! keeps a requested node in maintenance" do
    @node.update_columns(maintenance_requested: true)
    Nodes::MaintenanceTransitions.stub(:handle, @recorder) { Nodes::MaintenanceProjection.mark_unsupported!(@node) }
    assert @node.reload.maintenance
    assert_equal [true, true], @transitions.last
  end
end
