class MigrateImageSource < ActiveRecord::Migration[7.0]
  def up

    ContainerImage.all.each do |image|
      image.image_variants.create!(
        label: image.registry_image_tag,
        registry_image_tag: image.registry_image_tag.blank? ? "latest" : image.registry_image_tag,
        validated_tag: image.validated_tag.nil? ? false : image.validated_tag,
        validated_tag_updated: image.validated_tag_updated
      )

    end

  end
end
