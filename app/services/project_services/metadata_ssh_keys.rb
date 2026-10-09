##
# Store User Publish SSH Keys for a given project
#
module ProjectServices
  class MetadataSshKeys
    attr_accessor :deployment

    def initialize(deployment)
      self.deployment = deployment
    end

    # @param record_drop [Boolean] false on replay (AgentWorkers::PendingSyncWorker)
    # @param self_heal [Boolean] false on replay: never provision the tenant inline
    def perform(record_drop: true, self_heal: true)
      region = deployment&.region
      return false if region.nil?
      return false if Agent::TenantRegistry.deleting?(deployment.id)
      Agent::PendingSync.track(record_drop:, region:, project: deployment, kind: "managed_ssh_keys") do
        Agent::Client.new(deployment, region: region).put_managed("ssh_keys", data.to_json, self_heal:)
      end
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
