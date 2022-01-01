attributes :id, :name, :is_default, :billing_plan_id, :active, :q_containers, :q_dns_zones, :q_cr, :allow_local_volume, :bill_offline, :bill_suspended, :remove_stopped, :created_at, :updated_at
child :locations do
  attributes :id, :name
end
child :regions do
  attributes :id, :name
end
