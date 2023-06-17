attributes :id, :name, :label, :default_domain, :public_ip, :command,
           :is_load_balancer, :has_domain_management,
           :current_state, :auto_scale, :auto_scale_horizontal, :auto_scale_max,
           :labels, :created_at, :updated_at

child deployment: :project do
  attributes :id, :name
end

node :image do |i|

  {
    id: i.container_image.id,
    name: i.container_image.name,
    label: i.container_image.label,
    role: i.container_image.role,
    variant: {
      id: i.image_variant.id,
      label: i.image_variant.label,
      name: i.image_variant.friendly_name,
      path: i.image_variant.full_image_path,
      default: i.image_variant.is_default,
      sort: i.image_variant.version
    }
  }

end

node :package do |i|
  if i.package.nil?
    {}
  else
    {
      label: i.package.product.label,
      cpu: i.package.cpu,
      memory: i.package.memory,
      storage: i.package.storage,
      bandwidth: i.package.bandwidth,
      local_disk: i.package.local_disk,
      backup: i.package.backup,
      memory_swap: i.package.memory_swap,
      memory_swappiness: i.package.memory_swappiness
    }
  end
end

node :has_sftp do |i|
  i.requires_sftp_containers?
end
node :ingress_rules do |i|
  i.ingress_rules.pluck(:id)
end
node :product_id do |i|
  i.package&.product_id
end
node :bastions do |i|
  i.sftp_containers.pluck(:id)
end
node :domains do |i|
  i.domains.pluck(:id)
end
node :deployed_containers do |i|
  i.containers.count
end

node :help do |i|
  {
    general: image_content_general(i.container_image),
    ssh: image_content_ssh(i),
    remote: image_content_remote(i),
    domain: image_content_domain(i.container_image)
  }
end

node :links do |i|
  {
    project: "/api/projects/#{i.deployment&.id}",
    bastions: "/api/container_services/#{i.id}/bastions",
    containers: "/api/container_services/#{i.id}/containers",
    events: "/api/container_services/#{i.id}/events",
    ingress_rules: "/api/container_services/#{i.id}/ingress_rules",
    metadata: "/api/container_services/#{i.id}/metadata",
    logs: "/api/container_services/#{i.id}/logs",
    products: "/api/products"
  }
end
