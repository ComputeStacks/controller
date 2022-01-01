object @user
attributes :id, :fname, :lname, :email, :phone, :active, :is_admin, :api_key, :api_version, :external_id, :billing_plan_id, :currency, :confirmed_at, :confirmation_sent_at, :last_request_at, :last_sign_in_at, :current_sign_in_at, :sign_in_count, :reset_password_sent_at, :locked_at, :failed_attempts, :address1, :address2, :city, :state, :zip, :country, :vat, :company_name, :run_rate, :labels, :created_at, :updated_at
node :currency_symbol do |i|
  Money.new(1, i.currency).symbol
end
node :current_sign_in_ip do |user|
  user.current_sign_in_ip.to_s
end
node :last_sign_in_ip do |user|
  user.last_sign_in_ip.to_s
end
if @include_usage
  node :unprocessed_usage do |i|
    i.unprocessed_usage
  end
end
child({security_keys: :security_keys}, object_root: false) do
  attributes :id, :label, :is_type, :public_key, :created_at, :updated_at
end
child({billing_plan: :billing_plan}, object_root: false) do
  attributes :id, :name
end
child :user_group, object_root: false do
  attributes :id, :name
end
child({auths: :external_integrations}, object_root: false) do
  attributes :id, :username, :created_at, :updated_at
  child({provision_driver: :driver}, object_root: false) do
    attributes :id, :endpoint, :module_name, :created_at, :updated_at
  end
end
node :services do |i|
  {
      deployments: i.deployments.count,
      containers: i.deployed_containers.count,
      container_services: i.container_services.count,
      container_images: i.container_images.count,
      container_registries: i.container_registries.count,
      dns_zones: i.dns_zones.count
  }
end
