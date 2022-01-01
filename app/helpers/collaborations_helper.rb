module CollaborationsHelper

  def collaborations_path(collab)
    case collab
    when ContainerImageCollaborator
      "/collaborations/#{collab.id}-image"
    when ContainerRegistryCollaborator
      "/collaborations/#{collab.id}-registry"
    when DeploymentCollaborator
      "/collaborations/#{collab.id}-project"
    when Dns::ZoneCollaborator
      "/collaborations/#{collab.id}-zone"
    else
      nil
    end
  end

  def collaboration_resource_path(collab)
    case collab
    when ContainerImageCollaborator
      "/container_images/#{collab.container_image.id}"
    when ContainerRegistryCollaborator
      "/container_registry/#{collab.container_registry.id}"
    when DeploymentCollaborator
      "/deployments/#{collab.deployment.token}"
    when Dns::ZoneCollaborator
      "/dns/#{collab.dns_zone.id}"
    else
      nil
    end
  end

  def collaboration_resource_name(collab)
    case collab
    when ContainerImageCollaborator
      collab.container_image.label
    when ContainerRegistryCollaborator
      collab.container_registry.label
    when DeploymentCollaborator
      collab.deployment.name
    when Dns::ZoneCollaborator
      collab.dns_zone.name
    else
      nil
    end
  end

  def collab_content_warning
    b = Block.find_by(content_key: 'collaborate.warning')
    return "" unless b
    c = b.find_content_by_locale I18n.locale
    return "" if c.nil?
    c.body.html_safe
  end

  def collab_content_faq
    b = Block.find_by(content_key: 'collaborate.faq')
    return "" unless b
    c = b.find_content_by_locale I18n.locale
    return "" if c.nil?
    c.body.html_safe
  end

end
