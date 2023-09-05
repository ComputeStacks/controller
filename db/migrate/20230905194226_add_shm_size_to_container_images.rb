class AddShmSizeToContainerImages < ActiveRecord::Migration[7.0]
  def change
    add_column :container_images, :shm_size, :bigint, default: 0, null: false
    add_column :deployment_container_services, :shm_size, :bigint, default: 0, null: false
  end
end
