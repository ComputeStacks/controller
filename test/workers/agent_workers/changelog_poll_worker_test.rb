require "test_helper"
require "minitest/mock"

##
# Which nodes get their changelog polled. A node in maintenance is always polled:
# `disconnected` is a Docker ping and says nothing about the agent, and the
# playbook's `cs-agent maintenance on --wait` needs the poll's ack.
class AgentWorkers::ChangelogPollWorkerTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
    AgentWorkers::ChangelogPollWorker.clear
  end

  test "fan-out includes a disconnected node in maintenance" do
    @node.update_columns(disconnected: true, maintenance_requested: true)

    AgentWorkers::ChangelogPollWorker.new.perform

    assert_equal [@node.global_id.to_s], fanned_out
  end

  test "fan-out skips a disconnected node outside maintenance" do
    @node.update_columns(disconnected: true, maintenance_requested: false)

    AgentWorkers::ChangelogPollWorker.new.perform

    assert_empty fanned_out
  end

  test "fan-out includes an up node and skips one without a token" do
    AgentWorkers::ChangelogPollWorker.new.perform
    assert_equal [@node.global_id.to_s], fanned_out

    AgentWorkers::ChangelogPollWorker.clear
    @node.update_columns(agent_token_encrypted: nil)
    AgentWorkers::ChangelogPollWorker.new.perform
    assert_empty fanned_out
  end

  test "a disconnected node in maintenance is polled" do
    @node.update_columns(disconnected: true, maintenance_requested: true)
    assert polled?
  end

  test "a connected node in maintenance is polled" do
    @node.update_columns(maintenance_requested: true)
    assert polled?
  end

  test "a disconnected node outside maintenance is not polled" do
    @node.update_columns(disconnected: true, maintenance_requested: false)
    refute polled?
  end

  private

  def fanned_out
    AgentWorkers::ChangelogPollWorker.jobs.map { |j| j["args"].first.to_s }
  end

  def polled?
    called = false
    projector = Object.new
    projector.define_singleton_method(:call) { called = true }
    Agent::ChangelogProjector.stub(:new, ->(_node) { projector }) do
      AgentWorkers::ChangelogPollWorker.new.perform(@node.global_id.to_s)
    end
    called
  end
end
