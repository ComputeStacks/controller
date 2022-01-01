module ContainerServices
  module ServiceMetrics
    extend ActiveSupport::Concern

    # TEMPORARY
    # 0 == 'ok' 1 == 'warn' 2 == 'danger'
    # def resource_status
    #   status_code = 0
    #   return 4 if status == 'error'
    #   return 10 if containers.empty? && created_at > 4.minutes.ago
    #   return 3 if containers.empty?
    #   containers.each do |c|
    #     status_code = c.resource_status if c.resource_status > status_code
    #   end
    #   status_code
    # end

    ##
    # CPU

    def metric_cpu_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(container_cpu_usage_seconds_total' \
               "{#{metric_selector}}[50s])) by (name) * 100",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response
      return [] unless response['resultType'] == 'matrix'
      result = {}
      response['result'].each do |metric|
        data = []
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
        result[metric['metric']['name']] = data
      end
      result
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
      result = {}
      response['result'].each do |metric|
        data = []
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
        result[metric['metric']['name']] = data
      end
      result
    end

    ##
    # Memory

    def metric_mem_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(container_memory_rss' \
                "{#{metric_selector}}) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response
      return [] unless response['resultType'] == 'matrix'
      result = {}
      response['result'].each do |metric|
        data = []
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_i / Numeric::MEGABYTE ]
        end
        result[metric['metric']['name']] = data
      end
      result
    end

    def metric_swap_usage(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(container_memory_swap' \
                "{#{metric_selector}}) by (name)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response
      return [] unless response['resultType'] == 'matrix'
      result = {}
      response['result'].each do |metric|
        data = []
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_i / Numeric::MEGABYTE ]
        end
        result[metric['metric']['name']] = data
      end
      result
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
      result = {}
      response['result'].each do |metric|
        data = []
        metric['values'].each do |unit|
          data << [ Time.at(unit[0]), unit[1].to_f.round(2) ]
        end
        result[metric['metric']['name']] = data
      end
      result
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
      data = {}
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          t = unit[0]
          data[t] = data[t].nil? ? val.round(3) : (data[t] + val).round(3)
        end
      end
      data.map { |k,v| [ Time.at(k), v ] }
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
      data = {}
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          t = unit[0]
          data[t] = data[t].nil? ? val.round(3) : (data[t] + val).round(3)
        end
      end
      data.map { |k,v| [ Time.at(k), v ] }
    end

    def metric_lb_sessions(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(haproxy_server_current_sessions' \
               "{#{metric_lb_selector}}) by (region)",
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

    private

    def metric_selector
      %Q(container_label_com_computestacks_service_id="#{id}")
    end

    def metric_lb_selector
      %Q(proxy=~"#{ingress_rules.map { |i| "#{i.lb_proxy_name}" }.join('|')}")
    end
  end
end
