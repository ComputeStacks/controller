class RemoveRoleClassFromContainerImages < ActiveRecord::Migration[7.0]
  def change
    remove_column :container_images, :role_class, :string
  end
end
