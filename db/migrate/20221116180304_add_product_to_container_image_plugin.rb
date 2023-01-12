class AddProductToContainerImagePlugin < ActiveRecord::Migration[7.0]
  def change
    add_column :container_image_plugins, :product_id, :integer
    add_index :container_image_plugins, :product_id
    add_column :container_image_plugins, :is_optional, :boolean, default: false, null: false
  end
end
