attributes :id, :label, :resource_kind, :unit, :unit_type, :external_id, :group
child package: :package do
  attributes :id, :cpu, :memory, :storage, :bandwidth, :local_disk, :memory_swap, :memory_swappiness, :backup
end
