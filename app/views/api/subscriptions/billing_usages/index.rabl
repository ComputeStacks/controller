object false

node :billing_usages do
  @usages.map do |i|
    partial "api/subscriptions/billing_usages/usage", object: i
  end
end