require "test_helper"

class Nodes::MaintenanceTransitionsTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    @node.update_columns(maintenance_requested: false, maintenance_reason: nil, maintenance_gen: 41, maintenance_seq: 97,
      maintenance_holds: {})
    @node.reload
    clear_claims!
    NodeWorkers::HealthCheckWorker.jobs.clear
    LoadBalancerWorkers::DeployConfigWorker.jobs.clear
    AgentWorkers::ChangelogPollWorker.jobs.clear
    NodeWorkers::RecoverVolumeWorker.jobs.clear
    ContainerWorkers::DeferredPowerWorker.jobs.clear
  end

  teardown { clear_claims! }

  # Redis is shared with other test runs; never inherit (or leave) a claim.
  def clear_claims!
    Sidekiq.redis do |c|
      [true, false].each { |v| c.call("DEL", "node_maintenance_transition:#{@node.id}:#{v}:97:41") }
    end
  end

  def kicks
    NodeWorkers::HealthCheckWorker.jobs.size + AgentWorkers::ChangelogPollWorker.jobs.size
  end

  test "true -> false logs and kicks recovery exactly once, even when two writers race" do
    assert_difference -> { EventLog.where(locale: "node.maintenance.disable").count }, 1 do
      Nodes::MaintenanceTransitions.handle(@node, was: true, now: false)
      Nodes::MaintenanceTransitions.handle(@node, was: true, now: false)
    end
    assert_equal 1, NodeWorkers::HealthCheckWorker.jobs.size
    assert_equal [@node.global_id.to_s], NodeWorkers::HealthCheckWorker.jobs.first["args"]
    assert_equal 1, AgentWorkers::ChangelogPollWorker.jobs.size
    assert_empty NodeWorkers::RecoverVolumeWorker.jobs, "volumes never left the node"
    assert_equal [[@node.id]], ContainerWorkers::DeferredPowerWorker.jobs.map { |j| j["args"] }
    assert_includes EventLog.order(:id).last.nodes, @node
  end

  test "true -> false deploys the region's load balancer config" do
    lb = @node.region.load_balancer
    skip "fixture region has no load balancer" if lb.nil?
    Nodes::MaintenanceTransitions.handle(@node, was: true, now: false)
    assert_equal [lb.global_id.to_s], LoadBalancerWorkers::DeployConfigWorker.jobs.last["args"]
  end

  test "false -> true logs who holds it and kicks nothing" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel",
      maintenance_holds: {"local" => {"since" => 1, "reason" => "docker", "by" => "root"}})
    @node.reload
    assert_difference -> { EventLog.where(locale: "node.maintenance.enable").count }, 1 do
      Nodes::MaintenanceTransitions.handle(@node, was: false, now: true)
    end
    assert_equal "Held by controller (kernel) and node (docker).", EventLog.order(:id).last.state_reason
    assert_equal 0, kicks
    assert_empty LoadBalancerWorkers::DeployConfigWorker.jobs
  end

  test "no change does nothing" do
    assert_no_difference -> { EventLog.count } do
      Nodes::MaintenanceTransitions.handle(@node, was: true, now: true)
      Nodes::MaintenanceTransitions.handle(@node, was: false, now: false)
    end
    assert_equal 0, kicks
  end
end
