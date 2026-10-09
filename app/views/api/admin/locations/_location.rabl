attributes :id, :name, :fill_strategy, :fill_by_qty, :overcommit_memory, :overcommit_cpu, :created_at, :updated_at
node :maintenance_summary do |i|
  Nodes::MaintenanceStatusPresenter.summary(Node.where(region_id: i.regions.select(:id)), include_region: true)
end
node :pending_agent_syncs do |i|
  Nodes::MaintenanceStatusPresenter.pending_agent_syncs(i.regions.select(:id))
end
node :links do |i|
  {
    regions: "/api/admin/locations/#{i.id}/regions"
  }
end
