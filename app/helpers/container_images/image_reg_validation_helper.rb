module ContainerImages
  module ImageRegValidationHelper

    def image_valid_tag_label(image, hide_valid = false)
      if image.validated_tag && image.validated_tag_updated
        return nil if hide_valid
        %Q(<span class="label label-success"><i class="fa #{image_valid_tag_icon(image)} fa-fw"></i></span>).html_safe
      elsif image.validated_tag_updated
        %Q(<span class="label label-danger"><i class="fa #{image_valid_tag_icon(image)} fa-fw"></i></span>).html_safe
      else
        %Q(<span class="label label-default"><i class="fa #{image_valid_tag_icon(image)} fa-fw"></i></span>).html_safe
      end
    end

    def image_valid_tag_message(image)
      if image.validated_tag_updated && !image.validated_tag
        link = "#{request =~ /admin/ ? '/admin/' : '/'}container_images/#{image.id}/image_validation"
        %Q(
					<small class='text-danger'>Unable to pull image from registry.
					Last attempted: #{l(image.validated_tag_updated)}
					&middot; #{link_to("Try Again", link, method: :post)}
					</small>).html_safe
      elsif !image.validated_tag_updated
        %q(<small class='text-muted'>Validating connection to image registry...</small>).html_safe
      end
    end

    def image_list_header(image)
      if image.validated_tag_updated
        image.validated_tag ? 'panel-success' : 'panel-danger'
      else
        'panel-default'
      end
    end

    def image_list_header_title(image)
      if image.validated_tag_updated && image.validated_tag
        "Last validation at #{l(image.validated_tag_updated)}"
      elsif image.validated_tag_updated && !image.validated_tag
        'Error pulling image'
      else
        'Pending validation'
      end
    end

    def image_valid_tag_icon(image)
      if image.validated_tag && image.validated_tag_updated
        'fa-check'
      elsif image.validated_tag_updated
        'fa-ban'
      else
        'fa-refresh fa-spin'
      end
    end

    def table_image_icon(image)
      if image.validated_tag && image.validated_tag_updated
        tag.i nil, class: 'fa fa-check-circle', style: 'color: green;'
      elsif image.validated_tag_updated
        tag.i nil, class: 'fa fa-ban'
      else
        tag.i nil, class: 'fa-refresh fa-spin'
      end
    end

  end
end
