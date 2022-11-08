class AddProductIdToContainerImages < ActiveRecord::Migration[7.0]
  def change
    add_column :container_images, :product_id, :bigint
    add_index :container_images, :product_id
  end
end
