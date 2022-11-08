module ContainerImages
  module ImageRegValidationHelper

    def image_default_image_path(image)
      if image.image_variants.count == 1
        image.default_variant.full_image_path
      else
        "#{image.provider_path}#{image.provider_path.blank? ? '' : '/'}#{image.registry_image_path}"
      end
    end

    def image_valid_tag_label(image, hide_valid = false)
      status_class = case image.variant_pull_status
                     when :valid
                       hide_valid ? nil : 'success'
                     when :partial
                       'warning'
                     when :pending
                       'default'
                     when :invalid
                       'danger'
                     else
                       nil
                     end
      status_icon = case image.variant_pull_status
                    when :valid
                      'fa-check'
                    when :partial
                      'fa-exclamation-triangle'
                    when :pending
                      'fa-refresh fa-spin'
                    when :invalid
                      'fa-exclamation-triangle'
                    else
                      nil
                    end
      return nil if status_class.nil?
      %Q(<span class="label label-#{status_class}"><i class="fa #{status_icon} fa-fw"></i></span>).html_safe
    end

    def image_valid_tag_message(image)
      case image.variant_pull_status
      when :partial
        %q(<small class='text-danger'>Some image variants are not available.</small>).html_safe
      when :pending
        %q(<small class='text-muted'>Pending registry validation...</small>).html_safe
      when :invalid
        %q(<small class='text-muted'>Error connecting to registry, ensure settings are correct.</small>).html_safe
      else
        nil
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

    def table_image_icon(image)
      case image.variant_pull_status
      when :valid
        tag.i nil, class: 'fa fa-check-circle', style: 'color: green;'
      when :partial
        tag.i nil, class: 'fa-exclamation-triangle'
      when :pending
        tag.i nil, class: 'fa-refresh fa-spin'
      when :invalid
        tag.i nil, class: 'fa fa-ban'
      else
        nil
      end
    end

  end
end
