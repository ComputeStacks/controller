object false

node :billing_resource_price do
  partial 'api/admin/billing_plans/billing_resources/billing_phases/billing_resource_prices/price', object: @price
end

