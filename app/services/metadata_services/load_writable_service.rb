module MetadataServices
  ##
  # Clients are given write access to `db/` on the metadata service. Load that and parse.
  #
  # Reads the customer-writable /db space via the node agent's cross-tenant admin
  # API (Agent::Client) instead of Consul KV. NOTE: this service currently has no
  # callers — it's repointed to document intent for the rebuilt consumer.
  class LoadWritableService
    attr_reader :service

    # @param [Deployment::ContainerService] service
    def initialize(service)
      @service = service
    end

    def all
      agent.all_db
    rescue Agent::Client::NotReady
      ""
    end

    # @param [String] path "modules/database"
    def get(path)
      body = agent.get_db(path)
      body.blank? ? "[]" : body
    rescue Agent::Client::NotReady
      "[]"
    end

    # @param [String] path "modules/database"
    def get_json(path)
      Oj.load get(path)
    rescue Oj::ParseError, JSON::ParserError
      nil
    end

    protected

    def agent
      region = @service.region || @service.nodes.online.first&.region
      Agent::Client.new(@service.deployment, region: region)
    end
  end
end
