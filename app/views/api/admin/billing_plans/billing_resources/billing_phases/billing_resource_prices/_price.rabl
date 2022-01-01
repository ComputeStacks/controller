attributes :id, :billing_phase_id, :billing_resource_id, :currency, :max_qty, :price, :created_at, :updated_at
child :regions, object_root: false do
  attributes :id, :name
end
node :links do |i|
  {
    billing_plan: "/api/admin/billing_plans/#{i.billing_plan.id}",
    billing_resource: "/api/admin/billing_plans/#{i.billing_plan.id}/billing_resources/#{i.id}",
    billing_resource_phase: "/api/admin/billing_plans/#{i.billing_plan.id}/billing_resources/#{i.id}/billing_phases/#{i.id}",
  }
end
