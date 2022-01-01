object @usage
attributes :id, :period_start, :period_end, :external_id, :rate, :qty, :qty_total, :total, :processed, :processed_on, :created_at, :updated_at
child :subscription_product do
  attributes :id, :external_id, :start_on, :active, :phase_type, :created_at, :updated_at
  child :product do
    extends 'api/admin/products/product'
  end
end
child :user do
  extends 'api/admin/users/short'
end
