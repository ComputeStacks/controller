object false
node :projects do
  @projects.each do |i|
    {
      id: "#{i.id}-project",
      project: {
        id: i.deployment&.id,
        name: i.deployment&.name
      },
      owner: {
        id: i.resource_owner&.id,
        email: i.resource_owner&.email,
        full_name: i.resource_owner&.full_name
      }
    }
  end
end

node :domains do
  @domains.each do |i|
    {
      id: "#{i.id}-zone",
      zone: {
        id: i.dns_zone&.id,
        name: i.dns_zone&.name
      },
      owner: {
        id: i.resource_owner&.id,
        email: i.resource_owner&.email,
        full_name: i.resource_owner&.full_name
      }
    }
  end
end

node :images do
  @images.each do |i|
    {
      id: "#{i.id}-image",
      image: {
        id: i.container_image&.id,
        name: i.container_image&.label
      },
      owner: {
        id: i.resource_owner&.id,
        email: i.resource_owner&.email,
        full_name: i.resource_owner&.full_name
      }
    }
  end
end

node :registries do
  @registries.each do |i|
    {
      id: "#{i.id}-registry",
      registry: {
        id: i.container_registry&.id,
        name: i.container_registry&.name
      },
      owner: {
        id: i.resource_owner&.id,
        email: i.resource_owner&.email,
        full_name: i.resource_owner&.full_name
      }
    }
  end
end
