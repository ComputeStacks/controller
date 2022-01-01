object false

node :billing_resource_prices do
  @prices.map do |i|
    partial 'api/admin/billing_plans/billing_resources/billing_phases/billing_resource_prices/price', object: i
  end
end
