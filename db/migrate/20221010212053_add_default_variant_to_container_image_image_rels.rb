class AddDefaultVariantToContainerImageImageRels < ActiveRecord::Migration[7.0]
  def change
    add_column :container_image_image_rels, :default_variant_id, :bigint
    add_index :container_image_image_rels, :default_variant_id, name: 'image_rels_default_variant_index'
  end
end
