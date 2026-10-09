class CreateAgentPendingSyncs < ActiveRecord::Migration[7.2]
  # Dirty marks for agent writes that were dropped (agent unreachable, NotReady,
  # non-2xx). Each kind is a full-state idempotent push recomputed from the DB on
  # replay, so a row records only "(region, subject, kind, key) is out of sync".
  def change
    create_table :agent_pending_syncs do |t|
      t.references :region, null: false, foreign_key: {on_delete: :cascade}
      t.bigint :project_id, index: true
      t.references :node, foreign_key: {on_delete: :cascade}
      # tenant | tenant_delete | managed_metadata | managed_ssh_keys |
      # managed_sftp_host_keys | firewall
      t.string :kind, null: false
      # The sftp container name for managed_sftp_host_keys; "" otherwise.
      t.string :key, null: false, default: ""
      t.integer :generation, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :first_failed_at
      t.datetime :first_attempted_at
      t.datetime :last_attempt_at
      t.datetime :next_attempt_at
      t.datetime :dead_at
      t.timestamps
    end

    # Exactly one subject: a node for firewall, a project for everything else.
    add_check_constraint :agent_pending_syncs,
      "(kind = 'firewall' AND node_id IS NOT NULL AND project_id IS NULL) OR " \
      "(kind <> 'firewall' AND project_id IS NOT NULL AND node_id IS NULL)",
      name: "agent_pending_syncs_one_subject"

    add_index :agent_pending_syncs,
      "region_id, COALESCE(project_id, 0), COALESCE(node_id, 0), kind, key",
      unique: true, name: "index_agent_pending_syncs_on_subject"
    add_index :agent_pending_syncs, [:next_attempt_at, :dead_at]
  end
end
