object false
node :collaboration do
  case @collab
  when DeploymentCollaborator
    {
      id: "#{@collab.id}-project",
      project: {
        id: @collab.deployment&.id,
        name: @collab.deployment&.name
      }
    }
  when ContainerImageCollaborator
    {
      id: "#{@collab.id}-image",
      image: {
        id: @collab.container_image&.id,
        name: @collab.container_image&.label
      }
    }
  when ContainerRegistryCollaborator
    {
      id: "#{@collab.id}-registry",
      registry: {
        id: @collab.container_registry&.id,
        name: @collab.container_registry&.name
      }
    }
  when Dns::ZoneCollaborator
    {
      id: "#{@collab.id}-zone",
      zone: {
        id: @collab.dns_zone&.id,
        name: @collab.dns_zone&.name
      }
    }
  else
    {}
  end
end
node :resource_owner do
  {
    id: @collab.resource_owner&.id,
    email: @collab.resource_owner&.email,
    full_name: @collab.resource_owner&.full_name
  }
end
