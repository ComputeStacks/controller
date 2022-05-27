object false
node :collaboration do
  case @collab
  when DeploymentCollaborator
    {
      id: "#{@collab.id}-project",
      project: {
        id: @collab.deployment&.id,
        name: @collab.deployment&.name
      },
      created_at: @collab.created_at,
      updated_at: @collab.updated_at
    }
  when ContainerImageCollaborator
    {
      id: "#{@collab.id}-image",
      image: {
        id: @collab.container_image&.id,
        name: @collab.container_image&.label
      },
      created_at: @collab.created_at,
      updated_at: @collab.updated_at
    }
  when ContainerRegistryCollaborator
    {
      id: "#{@collab.id}-registry",
      registry: {
        id: @collab.container_registry&.id,
        name: @collab.container_registry&.name
      },
      created_at: @collab.created_at,
      updated_at: @collab.updated_at
    }
  when Dns::ZoneCollaborator
    {
      id: "#{@collab.id}-zone",
      zone: {
        id: @collab.dns_zone&.id,
        name: @collab.dns_zone&.name
      },
      created_at: @collab.created_at,
      updated_at: @collab.updated_at
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
node :collaborator do
  {
    id: @collab.collaborator&.id,
    email: @collab.collaborator&.email,
    full_name: @collab.collaborator&.full_name
  }
end
