class CreateContainerImageCustomHostEntries < ActiveRecord::Migration[6.1]
  def change
    create_table :container_image_custom_host_entries do |t|
      t.bigint :container_image_id
      t.string :hostname
      t.bigint :source_image_id

      t.timestamps
    end
    add_index :container_image_custom_host_entries, :container_image_id
    add_index :container_image_custom_host_entries, :source_image_id
  end
end
