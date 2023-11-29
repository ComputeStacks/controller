class AddInitToContainerImages < ActiveRecord::Migration[7.0]
  def change
    add_column :container_images, :docker_init, :boolean, default: false, null: false
  end
end
