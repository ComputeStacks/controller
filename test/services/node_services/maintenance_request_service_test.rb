require "test_helper"
require "minitest/mock"

class NodeServices::MaintenanceRequestServiceTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_gen: 5, maintenance_override_gen: nil, maintenance_holds: {})
    @node.reload
    @user = users(:admin)
    AgentWorkers::PushMaintenanceWorker.jobs.clear
  end

  def request!(**opts)
    NodeServices::MaintenanceRequestService.new(@node, actor: @user, remote_ip: "10.1.1.1", **opts).tap(&:perform)
  end

  test "entering bumps the generation, records the reason, and refreshes the caller's node" do
    svc = request!(on: true, reason: "  kernel upgrade  ")

    assert svc.changed?
    assert_equal 6, svc.gen
    assert @node.maintenance_requested
    assert @node.maintenance, "caller's node is reloaded with the derived value"
    assert_equal 6, @node.maintenance_gen
    assert_equal "kernel upgrade", @node.maintenance_reason
    assert_nil @node.maintenance_override_gen
    assert_in_delta Time.now.to_f, @node.maintenance_updated.to_f, 60
  end

  test "an unchanged request does not bump the generation but still pushes" do
    request!(on: true)
    AgentWorkers::PushMaintenanceWorker.jobs.clear

    svc = nil
    assert_no_difference -> { Audit.count } do
      assert_no_difference -> { EventLog.count } do
        svc = request!(on: true, reason: "retry")
      end
    end
    refute svc.changed?
    assert_equal 6, @node.reload.maintenance_gen
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
    assert_equal [@node.id], AgentWorkers::PushMaintenanceWorker.jobs.first["args"]
  end

  test "releasing when not requested is a no-op apart from the push" do
    svc = request!(on: false)
    refute svc.changed?
    assert_equal 5, @node.reload.maintenance_gen
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
  end

  test "release bumps the generation and clears a pending override" do
    @node.update_columns(maintenance_requested: true, maintenance_override_gen: 5)
    request!(on: false)
    @node.reload
    refute @node.maintenance_requested
    assert_equal 6, @node.maintenance_gen
    assert_nil @node.maintenance_override_gen
  end

  test "override ALWAYS bumps the generation and arms override_gen, even when not requested" do
    @node.update_columns(maintenance_holds: {"local" => {"by" => "root"}})
    svc = nil
    assert_difference -> { SystemEvent.where(event_code: "a70680386c4f8542").count }, 1 do
      svc = request!(on: true, override_all: true)
    end

    assert svc.changed?
    @node.reload
    refute @node.maintenance_requested, "override forces on: false"
    assert_equal 6, @node.maintenance_gen
    assert_equal 6, @node.maintenance_override_gen
    # The local hold stays until the agent confirms the release.
    assert @node.maintenance
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size

    request!(on: false, override_all: true)
    @node.reload
    assert_equal 7, @node.maintenance_gen
    assert_equal 7, @node.maintenance_override_gen
  end

  test "an override over a requested hold releases it" do
    @node.update_columns(maintenance_requested: true)
    request!(on: false, override_all: true)
    @node.reload
    refute @node.maintenance_requested
    assert_equal @node.maintenance_gen, @node.maintenance_override_gen
  end

  test "a change writes an Audit and an EventLog on the node" do
    assert_difference -> { Audit.count }, 1 do
      # The §7 transition writes its own "entered maintenance" log; count only the service's.
      assert_difference -> { EventLog.where(locale: "node.maintenance.requested").count }, 1 do
        request!(on: true, reason: "disk swap")
      end
    end
    audit = Audit.order(:id).last
    assert_equal "updated", audit.event
    assert_equal @node.id, audit.rel_id
    assert_equal "10.1.1.1", audit.ip_addr.to_s
    assert_equal @user, audit.user

    event = EventLog.where(locale: "node.maintenance.requested").order(:id).last
    assert_equal "disk swap", event.state_reason
    assert_equal audit, event.audit
    assert_includes event.nodes, @node

    assert_difference -> { EventLog.where(locale: "node.maintenance.released").count }, 1 do
      request!(on: false)
    end

    assert_difference -> { EventLog.where(locale: "node.maintenance.override").count }, 1 do
      request!(on: false, override_all: true)
    end
  end

  test "the event locales exist in every language" do
    %w[requested released override].each do |key|
      %i[en de fi fr nl].each do |locale|
        assert I18n.exists?("events.messages.node.maintenance.#{key}", locale),
          "missing events.messages.node.maintenance.#{key} for #{locale}"
      end
    end
  end

  test "transitions receive the effective value before and after" do
    calls = []
    Nodes::MaintenanceTransitions.stub(:handle, ->(node, was:, now:) { calls << [node.id, was, now] }) do
      request!(on: true)
      request!(on: true)
    end
    assert_equal [[@node.id, false, true], [@node.id, true, true]], calls
  end
end
