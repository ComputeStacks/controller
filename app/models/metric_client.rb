require 'prometheus/api_client'
##
# Prometheus Service
#
# Prometheus metrics from Google CAdvisor: https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md
#
# IDEAS FOR DATA
#
# * container_memory_failcnt	[Counter] Number of memory usage hits limits
# * container_memory_max_usage_bytes  [Guage] Maximum memory usage recorded (bytes)
#   * Use this to help determine if they need to scale
# * container_cpu_load_average_10s	[Gauge]	Value of container cpu load average over the last 10 seconds
# * container_fs_usage_bytes	[Gauge]	Number of bytes that are consumed by the container on this filesystem	bytes
#   * Does this include volumes?
# * container_processes	[Gauge]	Number of processes running inside the container
# * container_network_receive_bytes_total and container_network_transmit_bytes_total (use the rate query)
#
class MetricClient < ApplicationRecord

  has_many :regions, dependent: :nullify

  def call
    # https://github.com/prometheus/prometheus_api_client_ruby/blob/c5cf560fc299e61f60c9e0d03eb1256789f828a9/lib/prometheus/api_client/client.rb
    Prometheus::ApiClient.client(url: endpoint_with_auth, options: { open_timeout: 5, timeout: 8 })
  end

  def endpoint_with_auth
    return endpoint if username.blank? || password.blank?
    uri = endpoint.split("://")
    return nil if uri.count == 1 # missing protocol!
    "#{uri[0]}://#{username}:#{password}@#{uri[1]}"
  end


end
