object false

node :load_balancer do
  partial "api/load_balancers/lb", object: @load_balancer
end