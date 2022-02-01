require 'names_generator'
require 'json_web_token'

Monetize.assume_from_symbol = true
DEFAULT_CURRENCY = Money::Currency.new(ENV['CURRENCY']).symbol
begin
  COMPUTESTACKS_VERSION = File.read("#{Rails.root.to_s}/VERSION").strip
rescue
  COMPUTESTACKS_VERSION = "0"
end

CS_CDN_URL = "https://cdn.computestacks.net/cloud-portal"

NS_LIST = if Rails.env.production?
            %w(8.8.8.8 1.1.1.1 8.8.4.4 64.6.64.6 208.67.222.222 1.0.0.1)
          else
            ['127.0.0.1']
          end

PORTAL_HTTP_SCHEME = Rails.env.production? ? "https" : "http"

BYTE_TO_GB = Numeric::GIGABYTE.to_f # old: 1.074e+9 # 1024, not 1000
KILOBYTE_TO_GB = Numeric::GIGABYTE / 1024.0 # old: 1.049e+6 # 1024, not 1000

I18n.default_locale = ENV['LOCALE']

DockerVolumeLocal.configure ssh_key: ENV['CS_SSH_KEY']

SYSTEM_CONTAINER_NAMES = %w(
  alertmanager
  cadvisor
  calico-node
  consul
  fluentd
  grafana
  loki
  loki-logs
  loki-nginx
  prometheus
  prom-nginx
  vault-bootstrap
)
