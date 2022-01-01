object false

node :billing_usage do
  partial "api/subscriptions/billing_events/event", object: @usage
end

