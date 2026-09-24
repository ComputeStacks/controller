collection @domains, root: "domains", object_root: false
attributes :id, :domain, :system_domain, :header_hsts, :hsts_include_subdomains, :hsts_preload, :header_frame_options, :created_at, :updated_at
node :container_service do |i|
  i.container_service&.id
end
node :lets_encrypt do |i|
  if i.le_active?
    "active"
  else
    (i.le_enabled ? "pending" : "inactive")
  end
end
node :links do |i|
  if i.container_service
    {
      container_service: "/api/container_services/#{i.container_service.id}"
    }
  end
end
child :user do
  extends "api/admin/users/short"
end
child deployment: :project do
  attributes :id, :name
end
