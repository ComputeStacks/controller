module Regions
  module RegionMetrics
    extend ActiveSupport::Concern

    # Returns allocated usage as a %.
    def current_allocated_usage
      # .to_i is mandatory, not stylistic: total_cpu_cores / total_memory_mb answer nil
      # for a node whose capacity is unknown, Enumerable#sum starts at the integer 0,
      # and 0 + nil raises TypeError -- one node with a NULL column and an unreachable
      # metrics server would take the whole zone figure down.
      avail_cpu = nodes.sum { |i| i.total_cpu_cores.to_i }
      avail_mem = nodes.sum { |i| i.total_memory_mb.to_i }
      # BEHAVIOUR CHANGE, 2026-09-04: this figure now includes containers that have no
      # subscription -- project load balancers and images ordered with the free toggle,
      # 503 of 2310 in production. The old walk went container_services -> subscriptions,
      # so a container with no subscription produced no row and was invisible here, while
      # Node#allocated_resources (the gate applied later, at provision time) counted it.
      # The two gates disagreed, so a zone could accept an order that its node then
      # refused. The zone figure is correspondingly larger. Nothing renders it -- the only
      # caller is Location#next_region, and the admin dashboard's per-zone cells come from
      # #resource_usage (live Prometheus), which this does not touch.
      #
      # SFTP containers are scoped by NODE, not through the region's deployments
      # association: a project's sftp row records the node it actually runs on, and that
      # is what decides whose capacity it consumes. (Region#container_count reaches them
      # through deployments instead, which is a different question and left alone.)
      from_containers = Deployment::Container.allocated_resources containers
      from_sftp = Deployment::Sftp.allocated_resources Deployment::Sftp.where(node_id: nodes.select(:id))
      cpu = from_containers[:cpu] + from_sftp[:cpu]
      memory = from_containers[:memory] + from_sftp[:memory]
      {
        cpu: {
          used: cpu,
          available: avail_cpu,
          usage: avail_cpu.zero? ? 100 : ((cpu.to_f / avail_cpu) * 100).to_i
        },
        memory: {
          used: memory,
          available: avail_mem,
          usage: avail_mem.zero? ? 100 : ((memory.to_f / avail_mem) * 100).to_i
        }
      }
    end

    # Currently used to display stats on admin dashboard
    #
    # All the Prometheus reads this needs -- three per active node -- go out in
    # ONE concurrent batch via MetricReads, not one after another. Each is an HTTP
    # round trip to the zone's metric client, and the controller is not
    # necessarily near it: measured from Amsterdam against the San Jose zone, one
    # read is ~1.4s, so reading them in sequence made this method take ~4.8s and
    # left the dashboard's spinners up for five seconds. A zone in the same city
    # was ~0.24s and is unaffected either way.
    #
    # Each metric_* reader already rescues internally to nil / [], so one slow or
    # failing read still cannot take the others down with it -- that per-read
    # isolation is the reason this issues three reads rather than folding them
    # into one combined PromQL expression.
    def resource_usage
      # Preloaded, and forced to an array, BEFORE the batch runs: metric_selector
      # reads node.region.name and the query needs node.metric_client, and a lazy
      # association load inside a read thread would be swallowed by that reader's
      # own rescue and silently reported as a nil metric.
      active_nodes = nodes.where(active: true).includes(:region, :metric_client).to_a
      return empty_usage if active_nodes.empty?
      # Without a metric client every read would raise into its own rescue and
      # come back nil anyway; short-circuit rather than start doomed threads.
      return empty_usage if metric_client.nil?

      readings = Node.panel_metrics_for(active_nodes, metrics: %i[memory cpu disk])

      mem_usages = active_nodes.filter_map { |n| readings.dig(n.id, :memory) }
      cpu_usages = active_nodes.filter_map { |n| readings.dig(n.id, :cpu) }
      disk_usages = active_nodes.filter_map { |n| primary_disk_usage(readings.dig(n.id, :disk)) }

      mem_usages << 0.0 if mem_usages.empty?
      cpu_usages << 0.0 if cpu_usages.empty?
      disk_usages << 0.0 if disk_usages.empty?
      {
        cpu: cpu_usages.average&.round(4),
        memory: mem_usages.average&.round(4),
        disk: disk_usages.average&.round(4),
        containers: container_count
      }
    rescue => e
      ExceptionAlertService.new(e, "cdf613d0d76a98c7").perform
      {cpu: 0.0, memory: 0.0, disk: 0.0, containers: 0}
    end

    private

    # Same shape resource_usage returned for a zone with no active nodes before
    # this was batched: three zeroes and a real container count.
    def empty_usage
      {cpu: 0.0, memory: 0.0, disk: 0.0, containers: container_count}
    end

    # Choose the disk to report for a node. Priority is /var/lib/docker,
    # otherwise /. Unchanged from the pre-concurrency version.
    # @return [Float, nil]
    def primary_disk_usage(disks)
      return nil if disks.nil?
      primary = nil
      disks.each do |dd|
        if dd[:mountpoint] == "/"
          primary = dd if primary.nil? || primary[:mountpoint] != "/var/lib/docker"
        end
        primary = dd if dd[:mountpoint] == "/var/lib/docker"
      end
      primary && primary[:usage]
    end

    public

    def metric_list_regions
      metric_client.call.label("region")
    end
  end
end
