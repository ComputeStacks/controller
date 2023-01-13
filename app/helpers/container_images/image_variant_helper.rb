module ContainerImages
  module ImageVariantHelper

    def container_image_variants_path(image)
      return container_images_path if image.nil?
      "#{container_image_path(image)}/image_variants"
    end

    def new_container_image_variant_path(image)
      return container_images_path if image.nil?
      "#{container_image_variants_path(image)}/new"
    end

    def edit_container_image_variant_path(variant)
      return container_images_path if variant.nil?
      "#{container_image_variant_path(variant)}/edit"
    end

    def container_image_variant_path(variant)
      return container_images_path if variant.nil?
      "#{container_image_variants_path(variant.container_image)}/#{variant.id}"
    end

    def image_variant_valid_tag_label(variant)
      %Q(<span class="label label-success">#{image_variant_valid_tag_icon(variant)}</span>).html_safe
    end

    def image_variant_valid_tag_icon(variant)
      if variant.validated_tag && variant.validated_tag_updated
        icon('fa-solid', 'check')
      elsif variant.validated_tag_updated
        icon('fa-solid', 'ban')
      else
        icon('fa-solid fa-spin', 'rotate')
      end
    end

  end
end
