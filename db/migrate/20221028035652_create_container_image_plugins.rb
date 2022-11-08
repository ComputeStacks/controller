class CreateContainerImagePlugins < ActiveRecord::Migration[7.0]
  def change
    create_table :container_image_plugins do |t|
      t.string :name, null: false
      t.boolean :active, default: false, null: false

      t.timestamps
    end
    add_index :container_image_plugins, :name, unique: true
    add_index :container_image_plugins, :active
  end
end
