module IngressValidator
  extend ActiveSupport::Concern

  included do
    validates :port, presence: true
    validates :proto, inclusion: {in: %w(http https tcp tls udp)} # UDP support is coming in HAProxy v2.1
    # @see https://cbonte.github.io/haproxy-dconv/1.8/configuration.html#5.2-send-proxy
    validates :tcp_proxy_opt, inclusion: {in: %w(none send-proxy send-proxy-v2 send-proxy-v2-ssl send-proxy-v2-ssl-cn)}

    # When UDP is added, we need to disallow `backend_ssl`.
  end

end
