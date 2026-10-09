attributes :id, :label, :hostname, :primary_ip, :agent_host, :disconnected, :failed_health_checks, :active, :online_at, :disconnected_at, :public_ip, :region_id, :maintenance, :maintenance_updated, :job_status, :job_performed, :ssh_port, :volume_device, :block_write_bps, :block_read_bps, :block_write_iops, :block_read_iops, :customer_notice, :created_at, :updated_at
node :maintenance_status do |i|
  Nodes::MaintenanceStatusPresenter.new(i).as_json
end
# What customers see for this node (the API's `node_status`).
node :customer_status do |i|
  Nodes::CustomerStatusPresenter.for_node(i)
end
