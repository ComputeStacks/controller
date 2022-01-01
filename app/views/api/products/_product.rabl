attributes :id, :label, :kind, :resource_kind, :created_at, :updated_at
child package: :package do
  attributes :id, :cpu, :memory, :storage, :bandwidth, :local_disk, :memory_swap, :memory_swappiness
end
