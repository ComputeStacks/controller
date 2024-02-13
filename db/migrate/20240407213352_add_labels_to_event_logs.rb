class AddLabelsToEventLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :event_logs, :labels, :jsonb, default: {}, null: false
  end
end
