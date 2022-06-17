class AddSharedVolumes < ActiveRecord::Migration[6.1]
  def change
    add_column :container_image_volume_params, :mount_ro, :boolean, default: false, null: false
    add_column :container_image_volume_params, :source_volume_id, :bigint

    add_column :volumes, :template_id, :bigint

    add_index :container_image_volume_params, :source_volume_id
    add_index :volumes, :template_id
  end
end
