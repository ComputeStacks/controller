class CreateContainerImageCollections < ActiveRecord::Migration[7.0]
  def change
    create_table :container_image_collections do |t|
      t.string :label
      t.boolean :active, default: true, null: false
      t.integer :sort, default: 0, null: false

      t.timestamps
    end
    add_index :container_image_collections, :active
    add_index :container_image_collections, :sort
  end
end
