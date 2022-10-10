class RemoveImageFromServices < ActiveRecord::Migration[7.0]
  def change
    remove_column :deployment_container_services, :container_image_id
  end
end
