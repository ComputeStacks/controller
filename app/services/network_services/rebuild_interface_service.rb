module NetworkServices
  class RebuildInterfaceService
    attr_reader :network,
      :event

    def initialize(net, event)
      @network = net
      @event = event
    end

    def perform
      region = @network.region

      region.nodes.each do |node|
        unless node.online?
          @event.event_details.create!(
            data: "Node #{node.label} is offline, skipping.",
            event_code: "7667db33f054005c"
          )
          next
        end

        stopped_containers = []

        # Find just the containers that use this network on a given node.
        (node.containers + node.sftp_containers).each do |container|
          # Not a good way to directly query for their network
          next unless container.network == @network

          # Only rebuild running containers.
          stopped_containers << container if container.active?

          stop_container_result = Timeout.timeout(30) do
            if container.active?
              container.stop! @event
            else
              # For stopped containers, just remove it
              container.delete_from_node! @event
            end
          end

          unless stop_container_result
            @event.event_details.create!(
              data: "Error stopping container #{container.name}.",
              event_code: "64c57ffee4afe41c"
            )
            next
          end

          # Don't overload the node.
          sleep 2
        end

        # Delete existing networks
        existing_network = nil
        begin
          client = node.client(10)
          # Trash network
          existing_network = Docker::Network.get(@network.name, {}, client)
        rescue Docker::Error::NotFoundError # already off the node!
          existing_network = nil
        rescue => e
          ExceptionAlertService.new(e, "8db17435d0a6c0b7").perform
          @event.event_details.create!(
            data: "Error removing network: #{@network.name}: #{e.message}",
            event_code: "8db17435d0a6c0b7"
          )
        end
        existing_network&.remove

        # Create network
        new_network = NetworkServices::CreateBridgeNetworkService.new(@network, @event)
        unless new_network.perform
          @event.event_details.create!(
            data: "Error rebuilding network #{@network.name}, halting container rebuild on node #{node.label}.",
            event_code: "2b511eec12f921b8"
          )
        end

        # Rebuild containers
        stopped_containers.each do |sc|
          rebuild_service = PowerCycleContainerService.new(sc, "rebuild", @event.audit)
          rebuild_service.event = @event
          rebuild_service.perform

          # Don't overload the node.
          sleep 5
        end
      end
    rescue => e
      ExceptionAlertService.new(e, "4b48cc3f36d59633").perform
      @event.event_details.create!(data: "Fatal Error: #{e.message}", event_code: "4b48cc3f36d59633")
    end
  end
end
