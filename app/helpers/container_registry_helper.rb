module ContainerRegistryHelper

  def container_registry_path(registry)
    "/container_registry/#{registry.id}-#{registry.name.parameterize}"
  end

  def registry_panel_class(registry_status)
    case registry_status
      when 'deploying', 'working'
        'panel-primary'
      when 'deployed'
        'panel-success'
      when 'error'
        'panel-danger'
      else
        'panel-default'
    end
  end

  def container_registry_image_path(id, name)
    "#{request.path =~ /admin/ ? '/admin' : ''}/container_images/#{id}-#{name.parameterize}"
  end

  def link_reg_to_image_path(registry, image, tag)
    "#{request.path =~ /admin/ ? '/admin' : ''}/container_images/new?container_image[container_image_provider_id]=#{registry.container_image_provider.id}&container_image[registry_image_path]=#{image}&container_image[registry_image_tag]=#{tag}"
  end

end
