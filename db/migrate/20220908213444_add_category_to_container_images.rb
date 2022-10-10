class AddCategoryToContainerImages < ActiveRecord::Migration[7.0]
  def change
    add_column :container_images, :category, :string
    add_index :container_images, :category
  end
end
