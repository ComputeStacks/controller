module NetworkWorkers
  ##
  # Find zombie networks and clean them up
  class PrivateNetCleanupWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform
      Network.shared.active.each do |net|
        # Try normal way first, and set net ready to use
        net.child_networks.active.each do |child|
          next if child.deployment

          NetworkServices::TrashBridgeNetworkService.new(child).perform
        end

        # Now find zombie networks
        net.region.nodes.available.each do |node|
          # retry: false, and this loop covers every shared network in the install. An
          # unreachable daemon here used to raise out of `perform` and abandon every region
          # after this one -- including the parked rows that TrashBridgeNetworkService is
          # relying on this sweep to retry. Skip the node instead.
          docker_networks = begin
            Docker::Network.all({}, node.client(10))
          rescue => e
            ExceptionAlertService.new(e, "e03e223ac83bb578").perform
            next
          end

          docker_networks.each do |network|
            # Docker reports `Labels` as null, not {}, on a network that has none -- which is
            # every predefined network (bridge/host/none) on every node.
            labels = network.info["Labels"] || {}
            net_id = labels[Network::NETWORK_ID_LABEL]
            next if net_id.blank?

            deployment_id = labels[Network::DEPLOYMENT_ID_LABEL]
            next if deployment_id.blank?

            found_deployment = Deployment.find_by id: deployment_id
            # Skip if we found the deployment
            next if found_deployment

            found_network = Network.find_by id: net_id

            # For now, we're not removing completely unknown networks
            next if found_network.nil?

            # Unusual, so skip to be safe.
            next if found_network.active || found_network.deployment

            # Trash
            begin
              network.remove
            rescue Docker::Error::NotFoundError # already off the node!
              next
            rescue => e
              ExceptionAlertService.new(e, "e03e223ac83bb578").perform
              next
            end
          end
        end
      end
    end
  end
end
