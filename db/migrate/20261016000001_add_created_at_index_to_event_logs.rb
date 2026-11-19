class AddCreatedAtIndexToEventLogs < ActiveRecord::Migration[7.2]
  # Backs the admin event log timeframe filter, the `sorted` scope, and the 12-month prune.
  disable_ddl_transaction!

  def change
    add_index :event_logs, :created_at, algorithm: :concurrently
  end
end
