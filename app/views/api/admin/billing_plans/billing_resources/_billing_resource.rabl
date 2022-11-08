attributes :id, :billing_plan_id, :external_id, :product_id, :prorate, :created_at, :updated_at
node :links do |i|
  {
    billing_plan: "/api/admin/billing_plans/#{i.billing_plan_id}",
    billing_phases: "/api/admin/billing_plans/#{i.billing_plan_id}/billing_resources/#{i.id}/billing_phases",
    product: "/api/admin/products/#{i.product.id}"
  }
end
