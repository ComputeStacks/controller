##
# Store User Publish SSH Keys for a given project
#
module ProjectServices
  class MetadataSshKeys
    attr_accessor :deployment

    def initialize(deployment)
      self.deployment = deployment
    end

    def perform
      return false if deployment&.region.nil?
      Agent::Client.new(deployment, region: deployment.region).put_managed("ssh_keys", data.to_json)
    rescue Agent::Client::NotReady
      false
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
