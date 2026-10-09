class CreateAgentTenants < ActiveRecord::Migration[7.2]
  # Durable registry of the regions where a project's agent tenant exists, so a
  # project trash deprovisions every region it was ever provisioned in, even
  # when the project no longer has services there. project_id deliberately has
  # no FK: rows must outlive the Project row until the deprovision succeeds.
  def up
    create_table :agent_tenants do |t|
      t.bigint :project_id, null: false
      t.references :region, null: false, foreign_key: {on_delete: :cascade}
      t.datetime :provisioned_at
      t.datetime :deleting_at
      t.timestamps
    end
    add_index :agent_tenants, [:project_id, :region_id], unique: true

    # Backfill: every existing project in each region it occupies today
    # (deployed containers, sftp containers, private network).
    execute <<~SQL
      INSERT INTO agent_tenants (project_id, region_id, provisioned_at, created_at, updated_at)
      SELECT DISTINCT r.project_id, r.region_id, now(), now(), now()
      FROM (
        SELECT s.deployment_id AS project_id, s.region_id
          FROM deployment_container_services s
          JOIN deployment_containers c ON c.container_service_id = s.id
        UNION
        SELECT f.deployment_id, n.region_id
          FROM deployment_sftps f
          JOIN nodes n ON n.id = f.node_id
        UNION
        SELECT w.deployment_id, w.region_id
          FROM networks w
      ) r
      JOIN deployments d ON d.id = r.project_id
      JOIN regions g ON g.id = r.region_id
      WHERE r.project_id IS NOT NULL AND r.region_id IS NOT NULL
    SQL
  end

  def down
    drop_table :agent_tenants
  end
end
