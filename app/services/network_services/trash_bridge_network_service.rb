module NetworkServices
  class TrashBridgeNetworkService

    attr_reader :network

    # @param [Network] net
    def initialize(net)
      @network = net
    end

    # @return [Boolean]
    def perform
      # If we still have addresses, stop
      return false unless @network.addresses.empty?
      # if we have a project, stop
      return false unless @network.deployment.nil?

      region = @network.region

      # Some nodes are offline
      if region.nodes.online.count != region.nodes.count
        # Will be tried later
        return false
      end

      region.nodes.online.each do |node|
        begin
          client = node.client(10)
          # Trash network
          existing_network = Docker::Network.get(@network.name, {}, client)
        rescue Docker::Error::NotFoundError # already off the node!
          next
        rescue => e
          ExceptionAlertService.new(e, '23cd7b2c8715f112').perform
          next
        end
        existing_network.remove
      end
      make_ready!
    end

    private

    # Make ready for the next project
    def make_ready!
      @network.update active: false
    end

  end

end
