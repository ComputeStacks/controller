attributes :id, :from_status, :to_status, :from_phase, :to_phase, :from_resource_qty, :to_resource_qty, :created_at, :updated_at
child :subscription do |sub|
  extends 'api/admin/subscriptions/show', object: sub
end
child source_product: :source_product do |sp|
  extends 'api/admin/products/show', object: sp
end
child destination_product: :destination_product do |sp|
  extends 'api/admin/products/show', object: sp
end
