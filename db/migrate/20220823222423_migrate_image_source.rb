class MigrateImageSource < ActiveRecord::Migration[7.0]
  def up

    result = ActiveRecord::Base.connection.execute(%Q(select * from container_images))

    result.each do |item|
      ContainerImage::ImageVariant.create!(
        container_image_id: item["id"],
        label: item["registry_image_tag"],
        registry_image_tag: item["registry_image_tag"].blank? ? "latest" : item["registry_image_tag"],
        validated_tag: item["validated_tag"].blank? ? false : item["validated_tag"],
        validated_tag_updated: item["validated_tag_updated"],
        is_default: true
      )
    end

  end
end
