class CreateJoinTableContainerImagePluginContainerImage < ActiveRecord::Migration[7.0]
  def change
    create_join_table :container_image_plugins, :container_images do |t|
      t.index [:container_image_plugin_id, :container_image_id], unique: true, name: 'image_plugin_on_image_index'
      t.index [:container_image_id, :container_image_plugin_id], unique: true, name: 'image_on_image_plugin_index'
    end
  end
end
