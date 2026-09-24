class AddUniqueIndexToVolumeMaps < ActiveRecord::Migration[7.2]
  INDEX_NAME = "index_volume_maps_on_service_and_path".freeze

  # Close the concurrency hole that lets two cascades create two `is_owner` VolumeMaps at one
  # mount path on one service. `VolumeMap` only has a racy uniqueness validation, and the result
  # is a service that can never be rebuilt again: runtime_config emits two binds with the same
  # destination, Docker rejects the create with "Duplicate mount point" (which `build!` does not
  # rescue), and unpicking it afterwards means direct database work.
  #
  # Separate from 20260803000001 on purpose: this is the migration that can legitimately refuse
  # to run, and the column it is separated from is what `rake volumes:audit_mounts` needs in
  # order to tell the operator which maps to fix.
  def up
    return if index_exists?(:volume_maps, %i[container_service_id mount_path], name: INDEX_NAME)

    # Raw SQL on purpose — a migration must not depend on model code that may have moved on.
    #
    # `container_service_id IS NOT NULL` matches what the index will actually enforce: Postgres
    # treats NULLs as distinct, so rows with no service can never violate it and must not be
    # reported as blockers. `VolumeMap.only_services` exists because such rows have been seen.
    # `VolumeMountAudit::Auditor#load_duplicates` filters identically — the two halves of this
    # feature must agree on what a duplicate is.
    dupes = select_all(<<~SQL).to_a
      SELECT container_service_id, mount_path, COUNT(*) AS dupe_count
      FROM volume_maps
      WHERE container_service_id IS NOT NULL
      GROUP BY container_service_id, mount_path
      HAVING COUNT(*) > 1
      ORDER BY container_service_id, mount_path
    SQL

    if dupes.any?
      offenders = dupes.map { |r|
        "(container_service_id=#{r["container_service_id"]}, mount_path=#{r["mount_path"].inspect}) x#{r["dupe_count"]}"
      }.join(", ")
      raise <<~MSG
        Cannot add a unique index on volume_maps (container_service_id, mount_path): duplicates exist.

        Offending pairs: #{offenders}

        Each duplicate is a service Docker will refuse to rebuild. Resolve them first
        (`rake volumes:audit_mounts` reports them in context — its column is already in place
        from the preceding migration), then re-run this one.
      MSG
    end

    add_index :volume_maps, %i[container_service_id mount_path], unique: true, name: INDEX_NAME
  end

  def down
    remove_index :volume_maps, name: INDEX_NAME
  end
end
