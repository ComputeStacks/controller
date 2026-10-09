class AddMaintenanceHoldsToNodes < ActiveRecord::Migration[7.2]
  # Effective maintenance = the controller's request OR a hold the node placed
  # itself (cs-agent 3.4 `maintenance on`). The COALESCE is load-bearing: for
  # `{}` the `->` yields SQL NULL, `false OR NULL` is NULL, and every node would
  # silently drop out of Node.online / available / offline. jsonb_typeof is used
  # rather than IS NOT NULL because the agent sends `local: null`, and a jsonb
  # null is not an SQL NULL.
  EFFECTIVE_MAINTENANCE_SQL = "maintenance_requested OR COALESCE(jsonb_typeof(maintenance_holds -> 'local') = 'object', false)".freeze

  def up
    add_column :nodes, :maintenance_requested, :boolean, default: false, null: false
    execute "UPDATE nodes SET maintenance_requested = COALESCE(maintenance, false)"

    add_column :nodes, :maintenance_reason, :string
    add_column :nodes, :maintenance_gen, :bigint, default: 0, null: false
    add_column :nodes, :maintenance_override_gen, :bigint
    # Last projected agent payload, minus instance_id.
    add_column :nodes, :maintenance_holds, :jsonb, default: {}, null: false
    add_column :nodes, :maintenance_seq, :bigint, default: 0, null: false
    add_column :nodes, :agent_instance_id, :string
    # Work observed by the drift worker: {running, pending, quiesce, observed_at, mismatch_since}.
    add_column :nodes, :maintenance_status, :jsonb, default: {}, null: false
    add_column :nodes, :maintenance_reconnect_attempts, :integer, default: 0, null: false
    add_column :nodes, :agent_maintenance_unsupported_at, :datetime

    # Rails filters virtual columns out of INSERT/UPDATE, so any remaining write
    # to `maintenance` becomes a silent no-op. Writers go through
    # NodeServices::MaintenanceRequestService (requested) or
    # Nodes::MaintenanceProjection (holds).
    remove_column :nodes, :maintenance
    add_column :nodes, :maintenance, :virtual, type: :boolean, as: EFFECTIVE_MAINTENANCE_SQL, stored: true, null: false
  end

  def down
    # Copy the EFFECTIVE value, so a node held locally stays out of Node.online
    # under the old code. Run this before deploying the old image.
    add_column :nodes, :maintenance_legacy, :boolean, default: false
    execute "UPDATE nodes SET maintenance_legacy = maintenance"
    remove_column :nodes, :maintenance
    rename_column :nodes, :maintenance_legacy, :maintenance

    remove_column :nodes, :agent_maintenance_unsupported_at
    remove_column :nodes, :maintenance_reconnect_attempts
    remove_column :nodes, :maintenance_status
    remove_column :nodes, :agent_instance_id
    remove_column :nodes, :maintenance_seq
    remove_column :nodes, :maintenance_holds
    remove_column :nodes, :maintenance_override_gen
    remove_column :nodes, :maintenance_gen
    remove_column :nodes, :maintenance_reason
    remove_column :nodes, :maintenance_requested
  end
end
