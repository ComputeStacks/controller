attributes :id, :label, :external_id, :active, :run_rate, :created_at, :updated_at
child :subscription_products, object_root: false do
  attributes :id, :external_id, :start_on, :active, :phase_type, :created_at, :updated_at
  node :product do |p|
    partial 'api/products/product', object: p.product
  end
  child :billing_resource do
    attributes :id, :billing_plan_id, :external_id
  end
end
child :container do
  attributes :id, :name, :label, :load_balancer_id, :status, :cpu, :memory, :created_at, :updated_at
  child :container_image do
    attributes :id, :label, :description, :image_url
  end
  child :deployment do
    attributes :id, :name, :status, :created_at, :updated_at
  end
  child :service do
    attributes :id, :name, :label, :created_at, :updated_at
  end
  child :region do
    attributes :id, :name
  end
  child :node do
    attributes :id, :label, :hostname, :primary_ip, :public_ip
  end
end
child :user do
  attributes :id, :full_name, :email, :external_id
end
