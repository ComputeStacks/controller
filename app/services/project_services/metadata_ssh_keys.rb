##
# Store User Publish SSH Keys for a given project
#
module ProjectServices
  class MetadataSshKeys

    attr_accessor :deployment

    def initialize(deployment)
      self.deployment = deployment
      @consul_base = "projects/#{deployment.token}"
    end

    def perform
      Diplomat::Kv.put("#{@consul_base}/ssh_keys", data.to_json, deployment.region.consul_config)
    end

    def data
      {
        ssh_keys: ssh_user_keys
      }
    end

    def ssh_user_keys
      k = deployment.project_ssh_keys.pluck(:pubkey)
      deployment.user.ssh_keys.pluck(:pubkey).each do |i|
        k << i unless k.include?(i)
      end
      deployment.deployment_collaborators.active.each do |c|
        c.collaborator.ssh_keys.pluck(:pubkey).each do |i|
          k << i unless k.include?(i)
        end
      end
      k
    end

  end
end
