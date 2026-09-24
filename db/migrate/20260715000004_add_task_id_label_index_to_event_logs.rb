class AddTaskIdLabelIndexToEventLogs < ActiveRecord::Migration[7.2]
  # Agent::TaskReconciler correlates each active/needs-reconcile task to its EventLog via
  # `EventLog.where("labels ->> 'task_id' = ?", task.id)` — run per task every 15s. Without
  # an index on that jsonb expression it is a sequential scan of event_logs. A Postgres
  # expression index makes the lookup a plain index probe.
  def up
    execute <<~SQL
      CREATE INDEX IF NOT EXISTS index_event_logs_on_task_id_label
      ON event_logs ((labels ->> 'task_id'))
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_event_logs_on_task_id_label"
  end
end
