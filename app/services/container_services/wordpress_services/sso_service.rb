module ContainerServices::WordpressServices
  class SsoService

    attr_accessor :service,
                  :username,
                  :ttl,
                  :link

    # @param [Deployment::ContainerService] service
    def initialize(service, user = 'admin')
      self.service = service
      self.username = user
      self.ttl = 10.seconds
    end

    def perform
      return false if service.nil? || service.default_domain.nil?
      existing_key = service.secrets.find_by(key_name: "ec_key")
      # if the key is nil, then the container wont even have it
      return false if existing_key.nil?
      ec_key = Ed25519::SigningKey.new Base64.decode64(existing_key.decrypted)
      payload = Base64.strict_encode64(
        { username: username, exp: ttl.from_now.to_i }.to_json
      )
      signature = ec_key.sign payload
      sig_data = Base64.strict_encode64 signature
      self.link = "https://#{service.default_domain}/wp-admin/?cs_auth_payload=#{ERB::Util.url_encode(payload)}&cs_auth_sig=#{ERB::Util.url_encode(sig_data)}"
      true
    end

  end
end
