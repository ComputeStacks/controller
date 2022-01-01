attributes :id, :domain, :system_domain, :le_enabled, :ingress_rule_id, :header_hsts, :force_https, :created_at, :updated_at
node :container_service do |i|
  i.container_service&.id
end
node :lets_encrypt do |i|
  if i.le_active?
    'active'
  else
    i.le_enabled ? 'pending' : 'inactive'
  end
end
node :links do |i|
  if i.container_service
    {
      container_service: "/api/container_services/#{i.container_service.id}"
    }
  end
end
