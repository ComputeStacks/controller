class CreateJoinTableContainerImageCollectionsContainerImage < ActiveRecord::Migration[7.0]
  def change
    create_join_table :container_image_collections, :container_images do |t|
      t.index [:container_image_collection_id, :container_image_id], name: 'image_collection_on_images_index'
      t.index [:container_image_id, :container_image_collection_id], name: 'image_on_image_collections_index'
    end
  end
end
