module ProjectServices
  class CleanMetadata

    attr_accessor :deployment,
                  :region

    def initialize(deployment, region)
      self.deployment = deployment
      self.region = region
      @consul_base = "projects/#{deployment.token}"
    end

    def perform
      trash_kv!
      trash_token!
      trash_policy!
    end

    private

    def trash_kv!
      Diplomat::Kv.delete(@consul_base, region.consul_config.merge!({recurse: true}))
    rescue
      nil
    end

    def trash_token!
      Diplomat::Token.delete deployment.consul_auth_id, region.consul_config
    rescue
      nil
    end

    def trash_policy!
      Diplomat::Policy.delete deployment.consul_policy_id, region.consul_config
    rescue
      nil
    end

  end
end
