class MigrateServiceImages < ActiveRecord::Migration[7.0]
  def up

    Deployment::ContainerService.all.each do |i|

      image = ContainerImage.find i.container_image_id
      source = image.default_variant

      i.update_column :image_variant_id, source.id

    end

  end
end
