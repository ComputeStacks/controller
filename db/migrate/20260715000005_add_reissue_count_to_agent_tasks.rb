class AddReissueCountToAgentTasks < ActiveRecord::Migration[7.2]
  def change
    # Bounds the controller's re-issue of a failed volume.trash teardown DELETE — the agent
    # does not auto-retry a failed teardown (handoff §4); TaskReconciler re-issues up to a cap.
    add_column :agent_tasks, :reissue_count, :integer, default: 0, null: false
  end
end
