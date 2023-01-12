class CreateDeploymentContainerServiceServicePlugins < ActiveRecord::Migration[7.0]
  def change
    create_table :deployment_container_service_service_plugins do |t|
      t.bigint :deployment_container_service_id
      t.integer :container_image_plugin_id
      t.boolean :active
      t.boolean :is_optional

      t.timestamps
    end
    add_index :deployment_container_service_service_plugins, :deployment_container_service_id, name: "dcssp_dcs_id_index"
    add_index :deployment_container_service_service_plugins, :container_image_plugin_id, name: "dcssp_cip_id_index"
  end
end
