object @dns_zone
attributes :id, :name, :provider_ref, :is_app, :app_subdomain, :created_at, :updated_at
child :user do
  attributes :id, :full_name, :email, :external_id
end
node :records do
  @records
end
