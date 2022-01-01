collection @orders, root: 'orders', object_root: false
attributes :id, :status, :created_at, :updated_at
child deployment: :project do
  attributes :id, :name
end