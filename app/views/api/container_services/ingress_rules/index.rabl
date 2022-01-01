object false

node :ingress_rules do
	@ingress_rules.map do |i|
		partial "api/networks/ingress_rules/ingress_rule", object: i
	end
end