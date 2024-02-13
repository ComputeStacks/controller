require 'names_generator'
require 'json_web_token'

Monetize.assume_from_symbol = true
DEFAULT_CURRENCY = Money::Currency.new(ENV['CURRENCY'].nil? ? 'USD' : ENV['CURRENCY']).symbol
COMPUTESTACKS_VERSION = File.read("#{Rails.root}/VERSION").strip.freeze

# Load some defaults for test/dev
unless Rails.env.production?
  LB_DEFAULT_CERT_PATH = if `whoami`.strip == 'vagrant'
                           '/home/vagrant/.ssl_wildcard/sharedcert.pem' # This is created with vagrant provision.
                         else
                           "#{Rails.root}/lib/dev/test_wildcard_ssl/sharedcert-test-crt"
                         end
end
NS_LIST = if ENV['RESOLVER_LIST'].blank?
            %w[8.8.8.8 1.1.1.1 8.8.4.4 64.6.64.6 208.67.222.222 1.0.0.1]
          else
            ENV['RESOLVER_LIST'].split(',')
          end

NS_PORT = ENV['RESOLVER_PORT'].blank? ? 53 : ENV['RESOLVER_PORT'].to_i

PORTAL_HTTP_SCHEME = Rails.env.production? ? "https" : "http"

begin
  # Since users can set this during install, lets try to guess some possible commons words they may use to identify their installation.
  # We really want a unique name, and if they're just testing with 'dev' or 'demo', we want to generate a unique name.
  app_id_exclude = %w[default dev development local localhost demo trial test tester testing cs cstacks cmptstks computestacks docker containers poc]
  CS_APP_ID = if ENV['APP_ID'].blank? || app_id_exclude.include?(ENV['APP_ID'])
                Digest::SHA256.hexdigest(ENV['SECRET_KEY_BASE'])[-8...-1]
              else
                ENV['APP_ID']
              end
rescue
  CS_APP_ID = "".freeze
end

BYTE_TO_GB = Numeric::GIGABYTE.to_f # old: 1.074e+9 # 1024, not 1000
KILOBYTE_TO_GB = Numeric::GIGABYTE / 1024.0 # old: 1.049e+6 # 1024, not 1000

I18n.default_locale = ENV['LOCALE'].nil? ? 'en' : ENV['LOCALE']

DockerVolumeLocal.configure ssh_key: ENV['CS_SSH_KEY'].nil? ? "~/.ssh/id_rsa" : "#{Rails.root}/#{ENV['CS_SSH_KEY']}"

SYSTEM_CONTAINER_NAMES = %w[
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
].freeze
