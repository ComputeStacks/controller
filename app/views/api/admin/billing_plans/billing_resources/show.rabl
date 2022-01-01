object false

node :billing_resource do
  partial 'api/admin/billing_plans/billing_resources/billing_resource', object: @billing_resource
end

