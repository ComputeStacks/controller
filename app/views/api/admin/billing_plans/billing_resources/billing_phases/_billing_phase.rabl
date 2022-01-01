attributes :id, :billing_resource_id, :phase_type, :duration_unit, :duration_qty, :created_at, :updated_at
node :links do |i|
  {
    billing_plan: "/api/admin/billing_plans/#{i.billing_plan.id}",
    billing_resource: "/api/admin/billing_plans/#{i.billing_plan.id}/billing_resources/#{i.id}",
    billing_resource_prices: "/api/admin/billing_plans/#{i.billing_plan.id}/billing_resources/#{i.id}/billing_phases/#{i.id}/billing_resource_prices",
  }
end
