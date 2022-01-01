object false

node :ingress_rule do
	partial "api/networks/ingress_rules/ingress_rule", object: @ingress_rule
end

