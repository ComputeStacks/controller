class AddAwaitingMountToVolumes < ActiveRecord::Migration[7.2]
  # Deliberately additive and unconditional: this migration must ALWAYS succeed, because
  # `rake volumes:audit_mounts` — the tool that finds volumes the old broken cascade left
  # unmounted-but-backed-up, and that reports the duplicate maps blocking the unique index in
  # 20260803000002 — reads and writes this column. If the column and the unique index shipped
  # in one migration, a fleet with duplicate maps would roll the column back on the raise and
  # leave the operator with no way to run the very task the error message points them at.
  def change
    # awaiting_mount: the Volume row, its VolumeMap and the real docker volume all exist,
    # but no container has ever been CREATED with the bind, so the mount does not exist
    # inside any running container. Binds are baked at container-create time, so a volume
    # attached to an already-deployed service stays in this state until that service's next
    # natural rebuild. While the flag is set the agent must be told `backup: false` — borg
    # would otherwise produce a healthy-looking archive series of an empty volume.
    add_column :volumes, :awaiting_mount, :boolean, default: false, null: false

    # Partial: the interesting set is tiny and transient.
    add_index :volumes, :awaiting_mount, where: "awaiting_mount"
  end
end
