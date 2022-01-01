attributes :id,
           :port,
           :port_nat,
           :proto,
           :external_access,
           :backend_ssl,
           :tcp_proxy_opt,
           :tcp_lb,
           :created_at,
           :updated_at

node :load_balancer_rule_id do |i|
  i.load_balancer_rule&.id
end
node :internal_load_balancer_id do |i|
  i.internal_load_balancer&.id
end

node :links do |i|
  if i.internal_load_balancer
    {
      load_balancer_rule: "/container_images/#{i.container_image.id}/ingress_params/#{i.load_balancer_rule.id}",
      internal_load_balancer: "/container_images/#{i.internal_load_balancer.id}"
    }
  else
    {}
  end
end
