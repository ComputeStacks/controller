attributes :id, :name, :label, :status, :created_at, :updated_at
node :endpoint do |i|
  "#{Setting.registry_base_url}:#{i.port}"
end
node :username do |i|
  'admin'
end
node :password do |i|
  i.registry_password
end
node :images do |i|
  i.repositories
end
