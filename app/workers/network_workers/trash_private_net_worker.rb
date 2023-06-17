module NetworkWorkers
  class TrashPrivateNetWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(network_id)
      net = Network.find network_id
      NetworkServices::TrashBridgeNetworkService.new(net).perform
    end

  end
end
