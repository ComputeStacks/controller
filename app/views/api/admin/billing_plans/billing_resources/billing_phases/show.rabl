object false

node :billing_phase do
  partial 'api/admin/billing_plans/billing_resources/billing_phases/billing_phase', object: @phase
end

