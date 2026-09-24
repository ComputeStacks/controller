require "test_helper"

class AgentWorkers::ActionPruneWorkerTest < ActiveSupport::TestCase
  setup do
    @node = nodes(:testone)
  end

  def task(id:, status:, reconciled_status:, updated_at:)
    t = AgentTask.create!(id: id, name: "volume.backup", status: status, node_id: @node.id,
      reconciled_status: reconciled_status)
    t.update_columns(updated_at: updated_at)
    t
  end

  test "prunes only terminal, fully-reconciled, old agent_tasks" do
    prunable = task(id: "old-done", status: "completed", reconciled_status: "completed", updated_at: 8.days.ago)
    recent = task(id: "recent-done", status: "completed", reconciled_status: "completed", updated_at: 1.day.ago)
    unreconciled = task(id: "old-unrec", status: "completed", reconciled_status: "running", updated_at: 8.days.ago)
    active = task(id: "old-active", status: "running", reconciled_status: "running", updated_at: 8.days.ago)

    AgentWorkers::ActionPruneWorker.new.perform

    refute AgentTask.exists?(prunable.id), "old terminal+reconciled row should be pruned"
    assert AgentTask.exists?(recent.id), "recent row kept"
    assert AgentTask.exists?(unreconciled.id), "un-reconciled row kept"
    assert AgentTask.exists?(active.id), "active row kept"
  end
end
