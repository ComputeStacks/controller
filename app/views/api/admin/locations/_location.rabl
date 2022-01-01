attributes :id, :name, :fill_strategy, :fill_by_qty, :overcommit_memory, :overcommit_cpu, :created_at, :updated_at
node :links do |i|
  {
    regions: "/api/admin/locations/#{i.id}/regions"
  }
end
