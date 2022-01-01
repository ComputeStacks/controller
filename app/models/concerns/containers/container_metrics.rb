module Containers
  module ContainerMetrics
    extend ActiveSupport::Concern

    class_methods do

      def metric_all_containers
        response = metric_client.call.query(
          query: 'container_last_seen' \
                  "{name != '', job=\"cadvisor\"}"
        )
        return nil unless response
        return [] if response['result'].empty?
        data = []
        response['result'].each do |i|
          data << {
            id: i['metric']['id'].split('/').last,
            name: i['metric']['name'],
            image: i['metric']['image'],
            time: Time.at(i['value'][1].to_i)
          }
        end
        data
      end

    end

    ##
    # General

    def stats
      {
        cpu: metric_cpu[:cpu],
        mem: metric_mem_perc
      }
    end

    def metric_last_seen
      response = metric_client.call.query(
        query: 'container_last_seen' \
                "{#{metric_selector}}"
      )
      return nil unless response
      return nil unless response['result'][0]
      Time.at(response['result'][0]['value'][1].to_i)
    end

    # TODO: Rewrite container `resource_status` for new prometheus system.
    # def resource_status
      #   cache_key = "container_resources_#{id}"
      #   return 4 if status == 'error'
      #   Rails.cache.fetch(cache_key, force: reset_cache, expires_in: 10.minutes, unless: lambda { |i| [4,10].include?(i) }) do
      #     return 4 if status.nil? && deployment.health == 'error' # Something happened and the deployment stopped. Probably due to this container.
      #     return 10 if !is_built? && created_at > 4.minutes.ago
      #     return 3 unless is_built? # Not built.
      #     return 10 if state && (!state.is_pending && state.is_processing)
      #     return 10 if (status.nil? || status == 'error') && created_at > 3.minutes.ago # Possible error, but brand new.
      #     return 4 if status.nil? || status == 'error' # Fatal error, but built.
      #     begin
      #       current_stats = metrics_client.current_stats
      #     rescue
      #       return 10
      #     end
      #     if current_stats.dig(:memory, "usage_percent").nil? || current_stats.dig(:cpu, "usage_percent").nil?
      #       return 0
      #     end
      #     container_cpu_reading = current_stats.dig(:cpu, "usage_percent")
      #     return 11 if container_cpu_reading.nil?
      #     mem_reading = current_stats.dig(:memory, "usage_percent").round(2)
      #     cpu_reading = ( container_cpu_reading / cpu.to_f).round(2)
      #     return 2 if mem_reading > 85 || cpu_reading > 90
      #     return 1 if mem_reading > 70 || cpu_reading > 80
      #     0
      #   end
      # rescue # If data is missing or parent object went away, just default to 0. Not a super critical method.
    #   0
    # end

    ##
    # Memory

    def metric_mem_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(container_memory_rss' \
                "{#{metric_selector}})",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response
      return [] unless response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_i / Numeric::MEGABYTE ]
        end
      end
      data
    end

    def metric_swap_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(container_memory_swap' \
                "{#{metric_selector}})",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response
      return [] unless response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_i / Numeric::MEGABYTE ]
        end
      end
      data
    end

    def metric_mem
      response = metric_client.call.query(
        query: 'sum(container_memory_rss' \
                "{#{metric_selector}})"
      )
      return nil unless response
      return nil unless response['result'][0]
      {
        time: Time.at(response['result'][0]['value'][0]),
        memory: response['result'][0]['value'][1].to_f.round(4)
      }
    end

    def metric_mem_perc
      m = metric_mem
      return 0.0 if m.nil?
      usage = (m[:memory] / Numeric::MEGABYTE) / memory
      (usage * 100).round(2)
    end

    def metric_mem_throttled(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_memory_failcnt' \
               "{#{metric_selector}}[50s])) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
      end
      data
    end

    ##
    # CPU

    def metric_cpu
      cur = metric_cpu_usage(2.minutes.ago,Time.now)
      return { time: Time.now, cpu: 0.0 } if cur.empty?
      cur = cur[-1]
      {
        time: cur[0],
        cpu: cur[1]
      }
    end

    def metric_cpu_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_cpu_usage_seconds_total' \
               "{#{metric_selector}}[50s])) by (name) * 100",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
      end
      data
    end

    def metric_cpu_throttled(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_cpu_cfs_throttled_seconds_total' \
               "{#{metric_selector}}[50s])) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
      end
      data
    end

    ##
    # Networking

    def metric_net_combined(start_time, end_time)
      {
        tx: metric_net_tx(start_time, end_time),
        rx: metric_net_rx(start_time, end_time)
      }
    end

    def metric_net_tx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_network_transmit_bytes_total' \
               "{#{metric_selector}}[50s])) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          data << [ Time.at(unit[0]), val.round(3) ]
        end
      end
      data
    end

    def metric_net_rx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_network_receive_bytes_total' \
               "{#{metric_selector}}[50s])) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          data << [ Time.at(unit[0]), val.round(3) ]
        end
      end
      data
    end

    ##
    # LoadBalancer

    def metric_lb_combined(start_time, end_time)
      {
        tx: metric_lb_tx(start_time, end_time),
        rx: metric_lb_rx(start_time, end_time)
      }
    end

    def metric_lb_tx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(haproxy_server_bytes_in_total' \
               "{#{metric_lb_selector}}[50s])) by (proxy)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          data << [ Time.at(unit[0]), val.round(3) ]
        end
      end
      data
    end

    def metric_lb_rx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(haproxy_server_bytes_out_total' \
               "{#{metric_lb_selector}}[50s])) by (proxy)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          data << [ Time.at(unit[0]), val.round(3) ]
        end
      end
      data
    end

    def metric_lb_sessions(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'haproxy_server_current_sessions' \
               "{#{metric_lb_selector}}",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 15
      )
      return [] unless response
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_i ]
        end
      end
      data
    end

    # Retrieve total usage (in BYTES) on the load balancer
    def metric_lb_bytes_out
      response = metric_client.call.query(
        query: 'haproxy_server_bytes_out_total' \
               "{#{metric_lb_selector}}"
      )
      return 0.0 unless response
      bytes = 0.0
      response['result'].each do |metric|
        val = metric['value'][1].to_f
        next if val.zero?
        bytes += val
      end
      bytes
    end

    # Retrieve total usage (in BYTES) for a container
    def metric_bytes_out
      response = metric_client.call.query(
        query: 'container_network_transmit_bytes_total' \
               "{#{metric_selector}}"
      )
      return 0.0 unless response
      bytes = 0.0
      response['result'].each do |metric|
        val = metric['value'][1].to_f
        next if val.zero?
        bytes += val
      end
      bytes
    end

    def metric_current_disk_usage
      metric_disk_usage(1.hour.ago, Time.now)[0][1]
    rescue
      nil
    end

    ##
    # Container Disk Usage
    #
    # * Reports total usage on disk for this container, excluding volumes.
    # * This stops reporting when container is off.
    def metric_disk_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: "sum(container_fs_usage_bytes" \
                "{#{metric_selector}}) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 15
      )
      return [] unless response
      data = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), (unit[1].to_i / BYTE_TO_GB ).round(6)]
        end
      end
      data
    end

    private

    def metric_selector
      %Q(name="#{name}")
    end

    def metric_lb_selector
      %Q(server="#{name}")
    end

  end
end
