class CreateAgentRepositories < ActiveRecord::Migration[7.2]
  def change
    # Local projection of the cs-agent `repository` changelog: observed borg repo
    # state per volume, keyed by the repo/volume name. Replaces the old Consul
    # `borg/repository/<name>` read behind Volume#repo_info. Eventually-consistent
    # cache — the authoritative "archive created" signal is a completed volume.backup
    # task result, not this row.
    create_table :agent_repositories do |t|
      t.string :name, null: false               # volume/repo name (UUID); == changelog entity_id
      t.bigint :size_on_disk                     # deduplicated size on disk
      t.bigint :total_size                       # expanded total size
      t.jsonb :archives, default: [], null: false
      t.bigint :node_id
      t.bigint :changelog_seq
      t.datetime :agent_updated_at               # payload updated_at (agent clock)
      t.timestamps
    end

    add_index :agent_repositories, :name, unique: true
  end
end
