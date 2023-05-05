module Nodes
  # Prometheus Node Metrics
  module NodeMetrics
    extend ActiveSupport::Concern

    # def last_online
    #   metrics_client.last_online
    # end
    #
    # def in_offline_window?
    #   false
    #   #(last_online.nil? ? 1.hour.ago : last_online) < OFFLINE_WINDOW.ago
    # end

    def can_accept_package?(package)
      proceed = true
      # Sanity checking: Make sure the node even has enough cpu / memory
      if metric_cpu_cores[:cpu].to_f < package.cpu
        add_context! node_system_cpu_cores: { metric_cpu_cores: metric_cpu_cores[:cpu], requested_cpu: package.cpu.to_f }
        proceed = false
      end
      if metric_memory(:MB)[:memory] < package.memory
        add_context! node_system_memory: { metric_memory: metric_memory(:MB)[:memory], requested_memory: package.memory }
        proceed = false
      end

      unless location.overcommit_cpu
        if (metric_cpu_cores[:cpu].to_f - allocated_resources[:cpu]) < package.cpu
          add_context! no_overcommit_cpu: {
            total_node_cpu: metric_cpu_cores[:cpu].to_f,
            cpu_allocated: allocated_resources[:cpu].to_f,
            requested_cpu: package.cpu.to_f
          }
          proceed = false
        end
      end

      unless location.overcommit_memory
        if metric_memory(:MB)[:memory] - allocated_resources[:memory] < package.memory
          add_context! no_overcommit_memory: {
            total_node_memory: metric_memory(:MB)[:memory],
            memory_allocated: allocated_resources[:memory],
            requested_memory: package.memory
          }
          proceed = false
        end
      end

      proceed
    end

    def allocated_resources
      cpu = 0.0
      memory = 0
      containers.each do |c|
        if c.subscription.nil?
          cpu += c.cpu
          memory += c.memory
          next
        end
        next if c.subscription.package.nil?
        cpu += c.subscription.package.cpu
        memory += c.subscription.package.memory
      end
      { cpu: cpu, memory: memory }
    end

    # Last boot timstamp
    def last_boot_time
      response = metric_client.call.query(
        query: "node_boot_time_seconds{#{metric_selector}}"
      )
      return nil unless response
      return nil unless response['result'][0]
      Time.at response['result'][0]['value'][1].to_i
    rescue
      nil
    end

    # Number of CPU cores
    def metric_cpu_cores
      return { time: Time.now, cpu: 2 } if Rails.env.test?
      response = metric_client.call.query(
        query: "count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))"
      )
      return { time: Time.now, cpu: 0 } unless response
      return { time: Time.now, cpu: 0 } unless response['result'][0]
      {
        time: Time.at(response['result'][0]['value'][0]),
        cpu: response['result'][0]['value'][1].to_i
      }
    rescue
      { time: Time.now, cpu: 0 }
    end

    # Amount of memory
    def metric_memory(unit = :GB)
      return { time: Time.now, memory: 2048 } if Rails.env.test?
      response = metric_client.call.query(
        query: "node_memory_MemTotal_bytes{#{metric_selector}}"
      )
      return { time: Time.now, memory: 0 } unless response
      return { time: Time.now, memory: 0 } unless response['result'][0]
      if unit == :GB
        {
          time: Time.at(response['result'][0]['value'][0]),
          memory: (response['result'][0]['value'][1].to_f / Numeric::GIGABYTE).round(2)
        }
      else
        {
          time: Time.at(response['result'][0]['value'][0]),
          memory: (response['result'][0]['value'][1].to_i / Numeric::MEGABYTE)
        }
      end
    rescue
      { time: Time.now, memory: 0 }
    end

    # Returns amount of disk space in GB
    def metric_disk
      response = metric_client.call.query(
        query: "node_filesystem_size_bytes{#{metric_selector},mountpoint=~'/|/var/lib/docker',fstype!='rootfs'}"
      )
      return nil unless response
      response['result'].map  do |i|
        {
          mountpoint: i['metric']['mountpoint'],
          device: i['metric']['device'],
          size: (i['value'][1].to_f / Numeric::GIGABYTE).round(2)
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
      return nil unless response['result'][0]
      response['result'][0]['value'][1].to_f.round(2)
    rescue
      nil
    end

    # Returns available memory in MB
    def metric_memory_avail
      response = metric_client.call.query(
        query: "node_memory_MemAvailable_bytes{#{metric_selector}}"
      )
      return nil unless response
      return nil unless response['result'][0]
      (response['result'][0]['value'][1].to_i / Numeric::MEGABYTE)
    rescue
      nil
    end

    # CPU usage (%)
    def metric_cpu_usage
      response = metric_client.call.query(
        query: "(((count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))) - avg(sum by (mode)(irate(node_cpu_seconds_total{mode='idle',#{metric_selector}}[5m])))) * 100) / count(count(node_cpu_seconds_total{#{metric_selector}}) by (cpu))"
      )
      return nil unless response
      return nil unless response['result'][0]
      response['result'][0]['value'][1].to_f.round(2)
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
      response['result'].map  do |i|
        {
          mountpoint: i['metric']['mountpoint'],
          device: i['metric']['device'],
          usage: i['value'][1].to_f.round(2)
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
      return nil unless response['result'][0]
      response['result'][0]['value'][1].to_f.round(2)
    rescue
      nil
    end

    # Returns a list of all node names that it knows about
    def metric_list_nodes
      metric_client.call.label('node')
    end

    def metric_selector(job = "node-exporter")
      %Q(node="#{hostname}",region="#{region.name}",job=~"#{job}")
    end

  end
end
