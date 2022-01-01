object false

node :billing_resources do
  @billing_resources.map do |i|
    partial 'api/admin/billing_plans/billing_resources/billing_resource', object: i
  end
end
