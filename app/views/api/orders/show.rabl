object @order
attributes :id, :status, :order_data, :created_at, :updated_at
child deployment: :project do
  attributes :id, :name
end
child :location do
  attributes :id, :name
end