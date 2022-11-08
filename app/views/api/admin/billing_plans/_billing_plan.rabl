attributes :id, :name, :term, :created_at, :updated_at
child :user_groups, object_root: false do
  attributes :id, :name, :created_at, :updated_at
end
child :billing_resources, object_root: false do
  attributes :id, :external_id
  child :product, object_root: false do
    attributes :id, :label, :resource_kind, :unit, :unit_type, :external_id
    child package: :package do
      attributes :id, :cpu, :memory, :storage, :bandwidth, :local_disk, :memory_swap, :memory_swappiness, :backup
    end
  end
  child :billing_phases, object_root: false do
    attributes :id, :phase_type, :duration_unit, :duration_qty
    child :prices, object_root: false do
      attributes :id, :currency, :max_qty, :price
      child :regions, object_root: false do
        attributes :id, :name
      end
    end
  end
end
node :links do |i|
  {
    billing_resources: "/api/admin/billing_plans/#{i.id}/billing_resources"
  }
end
