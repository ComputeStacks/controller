module IngressRules
  module LoadBalancerMetrics
    extend ActiveSupport::Concern

    def metric_net_combined(start_time, end_time)
      {
        tx: metric_net_tx(start_time, end_time),
        rx: metric_net_rx(start_time, end_time)
      }
    end

    def metric_net_tx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(haproxy_backend_bytes_out_total' \
               "{#{metric_selector}}[50s])) by (proxy)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      metric_net_response response
    end

    def metric_net_rx(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'sum(rate(haproxy_backend_bytes_in_total' \
               "{#{metric_selector}}[50s])) by (proxy)",
        start: start_time.to_i,
        end: end_time.to_i,
        step: 30
      )
      return [] unless response && response['resultType'] == 'matrix'
      metric_net_response response
    end

    def metric_lb_sessions(start_time, end_time)
      response = metric_client.call.query_range(
        query: 'haproxy_server_current_sessions' \
               "{#{metric_selector}}",
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
    def metric_bytes_ou
      response = metric_client.call.query(
        query: 'haproxy_server_bytes_out_total' \
               "{#{metric_selector}}"
      )
      bytes = 0.0
      response['result'].each do |metric|
        val = metric['value'][1].to_f
        next if val.zero?
        bytes += val
      end
      bytes
    end

    private

    def metric_client
      region.metric_client
    end

    def metric_selector
      %Q(proxy="#{lb_proxy_name}")
    end

    def metric_net_response(data = [])
      return [] if data.empty?
      result = []
      response['result'].each do |metric|
        metric['values'].each do |unit|
          val = unit[1].to_f
          val = val.zero? ? 0.0 : (val / Numeric::MEGABYTE)
          result << [ Time.at(unit[0]), val.round(4) ]
        end
      end
      result
    end


  end
end
