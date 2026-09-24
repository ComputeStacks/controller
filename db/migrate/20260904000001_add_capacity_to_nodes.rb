class AddCapacityToNodes < ActiveRecord::Migration[7.2]
  def change
    # Persisted node capacity, refreshed each minute by NodeWorkers::HeartbeatWorker
    # from Docker.info. Placement used to read these two figures live from Prometheus
    # on every candidate node of every order, so an unreachable metrics server rejected
    # every node in the fleet and failed customer orders.
    #
    # All three are nullable with no default and there is deliberately no backfill:
    # Nodes::NodeMetrics#total_cpu_cores / #total_memory_mb keep the live Prometheus
    # read as the NULL fallback, so behaviour on migration day is identical to what it
    # was until the first heartbeat lands. A backfill would buy nothing and could only
    # fail against an unreachable fleet.
    add_column :nodes, :cpu_cores, :integer
    add_column :nodes, :memory_mb, :bigint

    # Surfaced on the admin node panel. Without it, a node whose Docker.info silently
    # never succeeds is indistinguishable from a healthy one, because unknown capacity
    # now fails OPEN.
    add_column :nodes, :capacity_updated_at, :datetime
  end
end
