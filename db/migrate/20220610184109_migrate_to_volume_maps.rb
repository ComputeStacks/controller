class MigrateToVolumeMaps < ActiveRecord::Migration[6.1]
  def up
    Volume.all.each do |vol|
      vol.volume_maps.create! container_service_id: vol.container_service_id, mount_path: vol.container_path, is_owner: true
    end
  end
  def down
    # nothing is required to revert this commit.
    true
  end
end
