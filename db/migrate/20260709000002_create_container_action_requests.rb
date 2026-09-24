class CreateContainerActionRequests < ActiveRecord::Migration[7.2]
  def change
    # Local projection of the cs-agent `action_request` changelog: one row per
    # container-requested action, keyed by the agent-generated `action_id`. The
    # controller reacts off this table's own state machine, never off re-reading
    # the log (see Agent::ChangelogProjector / ContainerActionServices::Dispatch).
    create_table :container_action_requests do |t|
      t.string :action_id, null: false        # agent ULID/UUID — dedupe key
      t.bigint :node_id                        # reporting node (provenance)
      t.string :project_id                     # raw payload id (== Deployment#id, as string)
      t.bigint :deployment_id                  # resolved at dispatch (nullable)
      t.string :action_type, null: false
      t.jsonb :params, default: {}, null: false
      t.string :status, default: "received", null: false
      t.string :state_reason
      t.integer :attempts, default: 0, null: false
      t.datetime :next_attempt_at
      t.bigint :changelog_seq                  # seq first seen at
      t.jsonb :result
      t.datetime :dispatched_at
      t.timestamps
    end

    add_index :container_action_requests, :action_id, unique: true
    add_index :container_action_requests, :status
    add_index :container_action_requests, :node_id
    add_index :container_action_requests, [:deployment_id, :action_type]
    add_index :container_action_requests, :next_attempt_at
  end
end
