class AddSourceImageToDeploymentContainerServices < ActiveRecord::Migration[7.0]
  def change
    add_column :deployment_container_services, :image_variant_id, :bigint
    add_index :deployment_container_services, :image_variant_id
  end
end
