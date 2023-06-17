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
      node = region.nodes.online.first
      client = node.client(3)
      # 1. ensure network does not already exist
      begin
        return true unless Docker::Network.get(@network.name, {}, client).info.empty?
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
      if docker_net.is_a?(Docker::Network)
        @network.update active: true
        true
      else
        false
      end
    rescue => e
      ExceptionAlertService.new(e, '29c824a801b8866d').perform
      false
    end

  end
end
