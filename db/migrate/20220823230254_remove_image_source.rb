class RemoveImageSource < ActiveRecord::Migration[7.0]
  def change
    remove_column :container_images, :registry_image_tag, :string
    remove_column :container_images, :validated_tag, :boolean
    remove_column :container_images, :validated_tag_updated, :datetime
  end
end
