collection @orders
attributes :id, :status, :created_at, :updated_at
child :user do
  attributes :id, :full_name, :email
end