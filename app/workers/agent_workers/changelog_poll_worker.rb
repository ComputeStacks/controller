module AgentWorkers
  ##
  # Pulls each online node's cs-agent changelog and projects new entries into local
  # `container_action_requests` rows. Projection ONLY — reaction (dispatch), retries
  # and reaping run independently in ActionSweepWorker, so an empty changelog or a
  # poll error never stalls them. Mirrors NodeWorkers::HeartbeatWorker's per-node
  # fan-out. No explicit queue → `default` → worker_system.
  class ChangelogPollWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(node_id = nil)
      if node_id.nil?
        Node.online.where.not(agent_token_encrypted: nil).each do |n|
          AgentWorkers::ChangelogPollWorker.perform_async n.global_id
        end
        return
      end

      node = GlobalID::Locator.locate node_id
      return if node.nil? || !node.online?

      Agent::ChangelogProjector.new(node).call
    rescue => e
      ExceptionAlertService.new(e, "143cabb17ad9ea4d").perform
    end
  end
end
