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
      node = region.nodes.online.first
      client = node.client(10)
      # Trash network
      existing_network = Docker::Network.get(@network.name, {}, client)
      existing_network.remove
      make_ready!
    rescue Docker::Error::NotFoundError # already off the node!
      make_ready!
      true
    rescue => e
      ExceptionAlertService.new(e, '23cd7b2c8715f112').perform
      false
    end

    private

    # Make ready for the next project
    def make_ready!
      @network.update active: false
    end

  end

end
