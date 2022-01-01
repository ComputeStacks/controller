collection @billing_plans, object_root: false, root: 'billing_plans'
attributes :id, :name, :created_at, :updated_at
child :user_groups, object_root: false do
  attributes :id, :name, :created_at, :updated_at
end
node :links do |i|
  {
    billing_resources: "/api/admin/billing_plans/#{i.id}/billing_resources"
  }
end
