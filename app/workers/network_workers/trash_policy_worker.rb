module NetworkWorkers
  class TrashPolicyWorker
    include Sidekiq::Worker

    sidekiq_options retry: 4, queue: 'dep'

    def perform(region_id, policy_name)
      return false if policy_name.blank?
      region = Region.find_by(id: region_id)
      return false if region.nil?
      node = region.nodes.online.first
      return false if node.nil?
      node.host_client.client.exec!("calicoctl delete policy #{policy_name}")
    end

  end
end
