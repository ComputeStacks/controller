class CreateVolumeMaps < ActiveRecord::Migration[6.1]
  def change
    create_table :volume_maps do |t|
      t.bigint :volume_id
      t.bigint :container_service_id
      t.boolean :mount_ro, default: false, null: false
      t.string :mount_path
      t.boolean :is_owner, default: false, null: false

      t.timestamps
    end
    add_index :volume_maps, :volume_id
    add_index :volume_maps, :container_service_id
    add_index :volume_maps, :is_owner
  end
end
