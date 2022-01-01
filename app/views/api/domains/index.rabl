collection @domains, root: 'domains', object_root: false
attributes :id, :domain, :system_domain, :header_hsts, :created_at, :updated_at
node :container_service do |i|
  i.container_service&.id
end
node :lets_encrypt do |i|
  i.le_active? ? 'active' : (i.le_enabled ? 'pending' : 'inactive')
end
node :links do |i|
  if i.container_service
    {
      container_service: "/api/container_services/#{i.container_service.id}"
    }
  end
end
