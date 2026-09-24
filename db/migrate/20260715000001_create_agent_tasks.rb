class CreateAgentTasks < ActiveRecord::Migration[7.2]
  def change
    # Local projection of the cs-agent `task` changelog (v3.0.0 — Consul retired):
    # one row per unit of work (volume.backup/restore, backup.delete/export,
    # volume.trash), keyed by the controller-supplied `id` (a UUID we mint, or the
    # agent's reserved `volume.trash:<name>` for teardown). Snapshot-upsert by id —
    # the same task re-appears at higher seqs as its status advances. The readiness
    # reconciler (Agent::TaskReconciler) reacts off state transitions here, gating
    # `reconciled_status` per transition.
    create_table :agent_tasks, id: :string do |t|
      t.string :name, null: false                # volume.backup|volume.restore|backup.delete|backup.export|volume.trash
      t.string :status, null: false              # pending|running|completed|failed|cancelled
      t.jsonb :result                            # terminal result: {last_backup} | {url,object_key,size,expiry} | {error,output}
      t.bigint :audit_id                          # correlation to the controller's pre-created Audit (nil for agent-originated)
      t.string :volume                            # volume name (UUID)
      t.bigint :node_id                           # reporting node (provenance)
      t.string :project_id                        # Deployment#id as string; "0" for detached volumes
      t.bigint :changelog_seq                     # seq of the latest projected snapshot
      t.string :reconciled_status                 # last status the reconciler has reacted to (CAS target)
      t.timestamps
    end

    add_index :agent_tasks, :status
    add_index :agent_tasks, :audit_id
    add_index :agent_tasks, :volume
    add_index :agent_tasks, :node_id
    add_index :agent_tasks, :reconciled_status
  end
end
