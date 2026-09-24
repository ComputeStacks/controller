module Nodes
  # Prometheus Node Metrics
  module NodeMetrics
    extend ActiveSupport::Concern

    # The metrics the admin node panel displays, mapped to the reader that
    # fetches each one. Single source of truth for what a panel costs: one
    # Prometheus round trip per entry, per node.
    PANEL_READERS = {
      boot_time: :last_boot_time,
      memory: :metric_memory_usage,
      cpu: :metric_cpu_usage,
      disk: :metric_disk_usage,
      load: :metric_load
    }.freeze

    class_methods do
      ##
      # Read the panel metrics for many nodes in ONE concurrent batch.
      #
      # Batched across nodes as well as across metrics because the admin node
      # list renders every node in the fleet in a single request. Read one node
      # at a time it cost nodes * metrics sequential round trips -- around 12s
      # per node against a distant zone, and the view issued nine reads per node
      # because it called the readers inline and repeatedly.
      #
      # @param nodes [Enumerable<Node>]
      # @param metrics [Array<Symbol>] subset of PANEL_READERS keys
      # @return [Hash{Integer => Hash{Symbol => Object}}] keyed by node id
      def panel_metrics_for(nodes, metrics: PANEL_READERS.keys)
        nodes = nodes.to_a
        return {} if nodes.empty?

        # Populated HERE, in the calling thread, not left to the caller.
        # metric_selector reads region.name and the query needs metric_client
        # (a has_one :through), so a node handed over without them makes every
        # read thread lazily load the same association: each leases a database
        # connection that executor.wrap holds for the entire round trip, and a
        # ConnectionTimeoutError would then be swallowed by the reader's own
        # rescue and rendered as though the node reported nothing. Preloader
        # skips associations that are already loaded, so a caller passing a
        # relation with `.includes(...)` costs nothing extra here.
        ActiveRecord::Associations::Preloader.new(
          records: nodes, associations: [:region, :metric_client]
        ).call

        readers = metrics.index_with { |m| PANEL_READERS.fetch(m) }
        tasks = {}
        nodes.each do |node|
          readers.each { |metric, reader| tasks[[node.id, metric]] = -> { node.public_send(reader) } }
        end

        MetricReads.all(tasks).each_with_object({}) do |((node_id, metric), value), acc|
          (acc[node_id] ||= {})[metric] = value
        end
      end
    end

    # def last_online
    #   metrics_client.last_online
    # end
    #
    # def in_offline_window?
    #   false
    #   #(last_online.nil? ? 1.hour.ago : last_online) < OFFLINE_WINDOW.ago
    # end

    ##
    # Total CPU cores on this node, or nil when capacity is UNKNOWN. Never zero.
    #
    # Prefers the column the heartbeat writes from Docker.info and falls back to the
    # live Prometheus read, so a node that has never heartbeated (or an install that
    # has not run the migration yet) degrades to the old behaviour rather than to an
    # outage. Both sources report zero when they fail, and zero is indistinguishable
    # from "this node has no CPUs" -- so it is translated to nil here, once, and every
    # caller decides for itself what unknown means.
    #
    # @return [Integer, nil]
    def total_cpu_cores
      return cpu_cores if cpu_cores.to_i.positive?
      live = metric_cpu_cores[:cpu].to_i
      live.positive? ? live : nil
    end

    ##
    # Total memory on this node in MB, or nil when capacity is UNKNOWN. Never zero.
    # See #total_cpu_cores.
    #
    # @return [Integer, nil]
    def total_memory_mb
      return memory_mb if memory_mb.to_i.positive?
      live = metric_memory(:MB)[:memory].to_i
      live.positive? ? live : nil
    end

    def can_accept_package?(package)
      proceed = true
      # Sanity checking: Make sure the node even has enough cpu / memory.
      #
      # nil means capacity could not be determined, and an unknown capacity ABSTAINS --
      # it does not reject. Both of these readers used to answer zero when the metrics
      # server was unreachable, and BillingPackage validates cpu > 0 / memory >= 256, so
      # a zero rejected every candidate node. With both overcommit flags on -- every
      # production location -- this pair is the ONLY capacity gate on the path, so one
      # unreachable Prometheus failed customer orders fleet-wide. Fail open instead:
      # a node whose capacity we cannot read is left to the gates below.
      #
      # Read once each. The old code called the reader twice per gate (once for the
      # comparison, again inside the add_context! payload), each an HTTP round trip.
      cores = total_cpu_cores
      if cores && cores.to_f < package.cpu
        add_context! node_system_cpu_cores: {node_cpu_cores: cores, requested_cpu: package.cpu.to_f}
        proceed = false
      end
      memory = total_memory_mb
      if memory && memory < package.memory
        add_context! node_system_memory: {node_memory_mb: memory, requested_memory: package.memory}
        proceed = false
      end

      # Read at most once, and only if a gate below actually needs it. The two blocks
      # referenced allocated_resources four times between them (including inside the
      # add_context! payloads) -- but they are also the ONLY things that read it, and with
      # both overcommit flags on, neither block runs. Computing it up front would add two
      # aggregate queries per candidate node to the provisioning path in exactly the
      # configuration where nothing reads the answer.
      allocated = nil

      # Same abstain rule for the capacity half of these gates: with unknown total
      # capacity there is no meaningful "how much is left". allocated_resources is
      # unaffected -- it comes from the containers' own columns, not from Prometheus.
      unless location.overcommit_cpu
        allocated ||= allocated_resources
        if cores && (cores.to_f - allocated[:cpu]) < package.cpu
          add_context! no_overcommit_cpu: {
            total_node_cpu: cores.to_f,
            cpu_allocated: allocated[:cpu].to_f,
            requested_cpu: package.cpu.to_f
          }
          proceed = false
        end
      end

      unless location.overcommit_memory
        allocated ||= allocated_resources
        if memory && (memory - allocated[:memory]) < package.memory
          add_context! no_overcommit_memory: {
            total_node_memory: memory,
            memory_allocated: allocated[:memory],
            requested_memory: package.memory
          }
          proceed = false
        end
      end

      proceed
    end

    # Everything this node is committed to run. See
    # Deployment::Container.allocated_resources for why the containers' own columns are
    # the correct source, and Deployment::Sftp::ALLOCATED_CPU for the SFTP figures --
    # those rows carry no resource columns, so they are counted at what the node enforces
    # for them. They occupy the node exactly like any other container.
    def allocated_resources
      from_containers = Deployment::Container.allocated_resources containers
      from_sftp = Deployment::Sftp.allocated_resources sftp_containers
      {
        cpu: from_containers[:cpu] + from_sftp[:cpu],
        memory: from_containers[:memory] + from_sftp[:memory]
      }
    end

    # Last boot timstamp
    def last_boot_time
      response = metric_client.call.query(
        query: "node_boot_time_seconds{#{metric_selector}}"
      )
      return nil unless response
      return nil unless response["result"][0]
      Time.at response["result"][0]["value"][1].to_i
    rescue
      nil
    end

    ##
    # Number of CPU cores, read live from Prometheus.
    #
    # Memoised per instance. Since the persisted capacity columns landed this is only
    # the fallback on the placement path, but the admin pages still reach it repeatedly
    # for the same node within one render, and each call is an HTTP round trip to the
    # zone's metrics server (~1.4s across an ocean).
    #
    # RISK, accepted: a FAILED read memoises too, and sticks for the life of the
    # object. Node instances here are per-request / per-job and discarded, so a failure
    # is re-read on the next one; do not hold a Node in a long-lived object and expect
    # this to recover.
    def metric_cpu_cores
      @metric_cpu_cores ||= read_metric_cpu_cores
    end

    ##
    # Amount of memory. Memoised per instance and KEYED BY UNIT -- :GB and :MB return
    # different numbers from the same query, so one slot would hand a caller the other
    # caller's units. See #metric_cpu_cores for the memoisation risk.
    def metric_memory(unit = :GB)
      @metric_memory ||= {}
      @metric_memory[unit] ||= read_metric_memory(unit)
    end

    private

    def read_metric_cpu_cores
      return {time: Time.now, cpu: 2} if Rails.env.test?
      response = metric_client.call.query(
        query: "count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))"
      )
      return {time: Time.now, cpu: 0} unless response
      return {time: Time.now, cpu: 0} unless response["result"][0]
      {
        time: Time.at(response["result"][0]["value"][0]),
        cpu: response["result"][0]["value"][1].to_i
      }
    rescue
      {time: Time.now, cpu: 0}
    end

    def read_metric_memory(unit = :GB)
      return {time: Time.now, memory: 2048} if Rails.env.test?
      response = metric_client.call.query(
        query: "node_memory_MemTotal_bytes{#{metric_selector}}"
      )
      return {time: Time.now, memory: 0} unless response
      return {time: Time.now, memory: 0} unless response["result"][0]
      if unit == :GB
        {
          time: Time.at(response["result"][0]["value"][0]),
          memory: (response["result"][0]["value"][1].to_f / Numeric::GIGABYTE).round(2)
        }
      else
        {
          time: Time.at(response["result"][0]["value"][0]),
          memory: (response["result"][0]["value"][1].to_i / Numeric::MEGABYTE)
        }
      end
    rescue
      {time: Time.now, memory: 0}
    end

    public

    # Returns amount of disk space in GB
    def metric_disk
      response = metric_client.call.query(
        query: "node_filesystem_size_bytes{#{metric_selector},mountpoint=~'/|/var/lib/docker',fstype!='rootfs'}"
      )
      return nil unless response
      response["result"].map do |i|
        {
          mountpoint: i["metric"]["mountpoint"],
          device: i["metric"]["device"],
          size: (i["value"][1].to_f / Numeric::GIGABYTE).round(2)
        }
      end
    rescue
      nil
    end

    # Memory usage (%)
    def metric_memory_usage
      response = metric_client.call.query(
        query: "100 - ((node_memory_MemAvailable_bytes{#{metric_selector}} * 100) / node_memory_MemTotal_bytes{#{metric_selector}})"
      )
      return nil unless response
      return nil unless response["result"][0]
      response["result"][0]["value"][1].to_f.round(2)
    rescue
      nil
    end

    # Returns available memory in MB
    def metric_memory_avail
      response = metric_client.call.query(
        query: "node_memory_MemAvailable_bytes{#{metric_selector}}"
      )
      return nil unless response
      return nil unless response["result"][0]
      (response["result"][0]["value"][1].to_i / Numeric::MEGABYTE)
    rescue
      nil
    end

    # CPU usage (%)
    def metric_cpu_usage
      response = metric_client.call.query(
        query: "(((count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))) - sum(rate(node_cpu_seconds_total{mode='idle',#{metric_selector}}[1m]))) * 100) / count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))"
      )
      return nil unless response
      return nil unless response["result"][0]
      response["result"][0]["value"][1].to_f.round(2)
    rescue
      nil
    end

    # Return disk usage (%)
    # Will only include disks mounted at: / or /var/lib/docker
    # Excludes rootfs
    def metric_disk_usage
      response = metric_client.call.query(
        query: "100 - ((node_filesystem_avail_bytes{#{metric_selector},mountpoint=~'/|/var/lib/docker',fstype!='rootfs'} * 100) / node_filesystem_size_bytes{#{metric_selector},mountpoint=~'/|/var/lib/docker',fstype!='rootfs'})"
      )
      return [] unless response
      response["result"].map do |i|
        {
          mountpoint: i["metric"]["mountpoint"],
          device: i["metric"]["device"],
          usage: i["value"][1].to_f.round(2)
        }
      end
    rescue
      []
    end

    # Return 5m avg load
    def metric_load
      response = metric_client.call.query(
        query: "avg(node_load5{#{metric_selector}})"
      )
      return nil unless response
      return nil unless response["result"][0]
      response["result"][0]["value"][1].to_f.round(2)
    rescue
      nil
    end

    # Returns a list of all node names that it knows about
    def metric_list_nodes
      metric_client.call.label("node")
    end

    def metric_selector(job = "node-exporter")
      %(node="#{hostname}",region="#{region.name}",job=~"#{job}")
    end
  end
end
