object current_user
attributes :id, :fname, :lname, :email, :phone, :address1, :address2, :city, :company_name, :country, :timezone, :c_sftp_pass, :zip, :vat, :state, :locale, :created_at, :updated_at
node :currency do |i|
  {
    code: i.currency,
    symbol: Money.new(1, i.currency).symbol
  }
end
# child({security_keys: :security_keys}, object_root: false) do
#   attributes :id, :label, :is_type, :public_key, :created_at, :updated_at
# end
child({billing_plan: :billing_plan}, object_root: false) do
  attributes :id, :name
end
# child({auths: :external_integrations}, object_root: false) do
#   attributes :id, :username, :created_at, :updated_at
#   child({provision_driver: :driver}, object_root: false) do
#     attributes :id, :endpoint, :module_name, :created_at, :updated_at
#   end
# end
node :services do |i|
  {
      projects: i.deployments.count,
      containers: i.deployed_containers.count,
      container_services: i.container_services.count,
      container_images: i.container_images.count,
      container_registries: i.container_registries.count,
      dns_zones: i.dns_zones.count
  }
end
node :quota do |i|
  i.current_quota
end
node :unprocessed_usage do |i|
  i.unprocessed_usage
end
