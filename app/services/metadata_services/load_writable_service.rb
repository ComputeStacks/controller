module MetadataServices
  ##
  # Clients are given write access to `db/` on the metadata service. Load that and parse
  class LoadWritableService

    attr_reader :service

    # @param [Deployment::ContainerService] service
    def initialize(service)
      @service = service
    end

    def all
      Diplomat::Kv.get_all("#{consul_base_path}", consul_config)
    end

    # @param [String] path "modules/database"
    def get(path)
      Diplomat::Kv.get("#{consul_base_path}/#{path}", consul_config)
    end

    # @param [String] path "modules/database"
    def get_json(path)
      Oj.load get(path)
    rescue JSON::ParserError
      nil
    end

    protected

    def consul_base_path
      "projects/#{@service.deployment.token}/db"
    end

    def consul_config
      return {} if Rails.env.test? # for test, we dont want any config here!
      return {} if @service.nodes.online.empty?
      dc = @service.region.nil? ? @service.nodes.online.first.region.name.strip.downcase : @service.region.name.strip.downcase
      token = @service.region.nil? ? @service.nodes.online.first.region.consul_token : @service.region.consul_token
      return {} if token.blank?
      consul_ip = @service.nodes.online.first.primary_ip
      {
        http_addr: Diplomat.configuration.options.empty? ? "http://#{consul_ip}:8500" : "https://#{consul_ip}:8501",
        dc: dc.blank? ? nil : dc,
        token: token
      }
    end

  end
end
