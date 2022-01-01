object @subscription
attributes :id, :label, :external_id, :active, :run_rate, :created_at, :updated_at
child :subscription_products, object_root: false do
  attributes :id, :external_id, :start_on, :active, :phase_type, :created_at, :updated_at
  child :product do
    extends 'api/admin/products/product'
  end
  child :billing_resource do
    attributes :id, :billing_plan_id, :external_id
  end
end
child :container do
  extends 'api/containers/container'
  child :region do
    attributes :id, :name
  end
  child :node do
    attributes :id, :label, :hostname, :primary_ip, :public_ip
  end
end
child :user do
  extends 'api/admin/users/short'
end
