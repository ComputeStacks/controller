module NetworkWorkers
  ##
  # Find zombie networks and clean them up
  class PrivateNetCleanupWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform
      Network.shared.active.each do |net|
        net.child_networks.active.each do |child|
          next if child.deployment
          NetworkWorkers::TrashPrivateNetWorker.perform_async child.id
        end
      end
    end

  end
end
