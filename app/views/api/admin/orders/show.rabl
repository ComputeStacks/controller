object @order
attributes :id, :status, :order_data, :created_at, :updated_at
child :user do
  attributes :id, :full_name, :email, :external_id
end
child :deployment do
  attributes :id, :name
end
child :location do
  attributes :id, :name
end