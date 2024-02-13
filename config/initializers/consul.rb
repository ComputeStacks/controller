consul_protocol = 'http'
if Rails.env.production? && Pathname.new("/root/.consul/cert.pem").exist?
  client_cert = OpenSSL::X509::Certificate.new(File.read('/root/.consul/cert.pem'))
  client_key = OpenSSL::PKey.read(File.read('/root/.consul/key.pem'))
  Diplomat.configure do |config|
    config.options = {
      ssl: {
        ca_file: '/root/.consul/ca.pem',
        client_cert: client_cert,
        client_key: client_key,
        verify: true
      }
    }
  end
  consul_protocol = 'https'
elsif !Rails.env.production? && Pathname.new("lib/dev/ssl/consul/ca.pem").exist?
  client_cert = OpenSSL::X509::Certificate.new(File.read('lib/dev/ssl/consul/cert.pem'))
  client_key = OpenSSL::PKey.read(File.read('lib/dev/ssl/consul/key.pem'))
  Diplomat.configure do |config|
    config.options = {
      ssl: {
        ca_file: 'lib/dev/ssl/consul/ca.pem',
        client_cert: client_cert,
        client_key: client_key,
        verify: true
      }
    }
  end
  consul_protocol = 'https'
end
CONSUL_API_PROTO = consul_protocol.freeze
CONSUL_API_PORT = (CONSUL_API_PROTO == 'https' ? 8501 : 8500).freeze
