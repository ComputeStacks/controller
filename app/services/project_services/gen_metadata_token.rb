module ProjectServices
  class GenMetadataToken

    attr_accessor :deployment,
                  :policy,
                  :token,
                  :errors

    def initialize(deployment)
      self.deployment = deployment
      self.errors = []
    end

    def perform
      return true unless valid?
      init_policy
      if policy.nil?
        errors << "Missing Policy"
        return false
      end
      init_token
      if token.nil?
        errors << "Missing Token"
        return false
      end
      deployment.update consul_policy_id: policy["ID"],
                        consul_auth_id: token["AccessorID"],
                        consul_auth_key: token["SecretID"]
    end

    private

    def valid?
      deployment.consul_policy_id.blank? && deployment.consul_auth_id.blank? && deployment.consul_auth_key.blank?
    end

    def init_policy
      self.policy = Diplomat::Policy.create({
                                         Name: "proj-#{deployment.token}",
                                         Description: "MetaData Policy for Project #{deployment.name}",
                                         Rules: %Q(key_prefix "projects/#{deployment.token}/" { policy = "read" } key_prefix "projects/#{deployment.token}/db/" { policy = "write" })
                                       }, deployment.region.consul_config)

    end

    def init_token
      self.token = Diplomat::Token.create({
                                            Description: "MetaData Token for Project #{deployment.name}",
                                            Policies: [{Name: "proj-#{deployment.token}"}]
                                          }, deployment.region.consul_config)
    end

  end
end
