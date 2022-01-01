collection @subscriptions, object_root: false, root: 'subscriptions'
attributes :id, :label, :external_id, :active, :created_at, :updated_at
child :user do
  attributes :id, :full_name, :email, :external_id
end
