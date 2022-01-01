attributes :id, :period_start, :period_end, :external_id, :rate, :qty, :total, :processed, :processed_on, :created_at, :updated_at
node :product do |p|
  partial 'api/products/product', object: p.product
end
child :user do
  attributes :id, :full_name, :email, :external_id
end