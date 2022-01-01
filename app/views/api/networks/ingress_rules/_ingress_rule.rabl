attributes :id,
           :port,
           :port_nat,
           :proto,
           :external_access,
           :backend_ssl,
           :tcp_proxy_opt,
           :redirect_ssl,
           :restrict_cf,
           :tcp_lb,
           :created_at,
           :container_service_id,
           :updated_at

node :load_balancer_rule_id do |i|
  i.load_balancer_rule&.id
end
node :internal_load_balancer_id do |i|
  i.internal_load_balancer&.id
end

node :load_balanced_rules do |i|
  i.load_balanced_rules.map do |ii|
    partial "api/container_services/ingress_rules/ingress", object: ii
  end
end

node :links do |i|
  if i.internal_load_balancer
    {
      load_balancer_rule: "/api/container_services/#{i.container_service.id}/ingress_rules/#{i.load_balancer_rule.id}",
      internal_load_balancer: "/api/container_services/#{i.internal_load_balancer.id}",
      domains: "/api/network/ingress_rules/#{i.id}/domains"
    }
  else
    {
      domains: "/api/network/ingress_rules/#{i.id}/domains"
    }
  end
end
