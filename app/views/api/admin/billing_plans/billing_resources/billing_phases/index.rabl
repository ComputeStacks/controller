object false

node :billing_phases do
  @billing_phases.map do |i|
    partial 'api/admin/billing_plans/billing_resources/billing_phases/billing_phase', object: i
  end
end
