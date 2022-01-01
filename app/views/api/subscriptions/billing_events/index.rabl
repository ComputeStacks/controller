object false

node :billing_events do
  @billing_events.map do |i|
    partial "api/subscriptions/billing_events/event", object: i
  end
end