module ContainerImages
  module ImageVariantHelper

    def new_container_image_variant_path(image)
      return nil if image.nil?
      "#{container_image_path(image)}/image_variants/new"
    end

    def edit_container_image_variant_path(variant)
      return "/container_images" if variant.nil?
      "#{container_image_env_path(variant)}/edit"
    end

    def container_image_variant_path(variant)
      return "/container_images" if variant.nil?
      "#{container_image_path(variant.container_image)}/image_variants/#{variant.id}"
    end

    def image_variant_valid_tag_label(variant)
      %Q(<span class="label label-success"><i class="fa #{image_variant_valid_tag_icon(variant)} fa-fw"></i></span>).html_safe
    end

    def image_variant_valid_tag_icon(variant)
      if variant.validated_tag && variant.validated_tag_updated
        'fa-check'
      elsif variant.validated_tag_updated
        'fa-ban'
      else
        'fa-refresh fa-spin'
      end
    end

  end
end
