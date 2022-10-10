class CreateContainerImageImageVariants < ActiveRecord::Migration[7.0]
  def change
    create_table :container_image_image_variants do |t|
      t.string :label
      t.boolean :is_default, default: false, null: false
      t.integer :version, default: 0, null: false
      t.string :registry_image_tag
      t.text :before_migrate
      t.text :after_migrate
      t.text :rollback_migrate
      t.boolean :validated_tag, default: false, null: false
      t.datetime :validated_tag_updated
      t.bigint :container_image_id

      t.timestamps
    end
    add_index :container_image_image_variants, :container_image_id
    add_index :container_image_image_variants, :is_default
  end
end
