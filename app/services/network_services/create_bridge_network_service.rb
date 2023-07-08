module NetworkServices
  class CreateBridgeNetworkService

    attr_reader :network,
                :event

    # @param [Network] net
    # @param [EventLog] event
    def initialize(net, event)
      @network = net
      @event = event
    end

    def perform
      region = @network.region

      # The intention is that AZ's with bridged networks would only have a single node,
      # but for existing clusters that wish to migrate to bridged networks, this brings
      # some kind of support by just automatically including all networks on all nodes.
      results = []
      region.nodes.online.each do |node|
        client = node.client(3)
        # 1. ensure network does not already exist
        begin
          next unless Docker::Network.get(@network.name, {}, client).info.empty?
        rescue Docker::Error::NotFoundError
          # nothing
        end
        # 2. create network
        docker_net = Docker::Network.create(@network.name, {
          'IPAM' => {
            'Config' => [{ 'Subnet' => @network.to_net }]
          },
          'Labels' => {
            'com.computestacks.deployment_id' => @network.deployment.id.to_s,
            'com.computestacks.network_id' => @network.id.to_s
          }
        }, client)
        results << docker_net if docker_net.is_a?(Docker::Network)
      end
      return false if results.empty?
      @network.update active: true
      true
    rescue => e
      ExceptionAlertService.new(e, '29c824a801b8866d').perform
      false
    end

  end
end
