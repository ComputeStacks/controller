module NetworkServices
  class TrashBridgeNetworkService
    attr_reader :network

    # @param [Network] net
    def initialize(net)
      @network = net
    end

    ##
    # Remove this network from every node in its region and return the row to the free pool.
    #
    # `make_ready!` is the point of no return: it sets `active: false`, which is the only
    # thing keeping the row out of `GenerateProjectNetworkService`'s allocation pool. Once
    # the row is reallocated it is RENAMED, and the name is the only handle we have on the
    # docker network -- so a copy left on a node at that moment can never be found by name
    # again, and it holds the subnet forever. The next project to draw that row gets a 403
    # from docker ("Pool overlaps with other one on this address space") and cannot be
    # provisioned at all.
    #
    # So `make_ready!` runs only when every online node was positively confirmed clean:
    # either it never had the network, or we removed it. Any error -- an unreachable daemon,
    # a timeout, a removal docker refused -- leaves the row active, and the ten-minute
    # `NetworkWorkers::PrivateNetCleanupWorker` sweep retries it. Being slow to free a row is
    # cheap; freeing one whose network is still on a node is not.
    #
    # @return [Boolean]
    def perform
      # If we still have addresses, stop
      return false unless @network.addresses.empty?
      # if we have a project, stop
      return false unless @network.deployment.nil?

      region = @network.region
      return false if region.nil?

      # No node to confirm against means we cannot establish that the network is gone, and
      # "no nodes online" would otherwise satisfy the loop vacuously.
      return false if region.nodes.empty?

      # Some nodes are offline
      if region.nodes.online.count != region.nodes.count
        # Will be tried later
        return false
      end

      confirmed_clean = true
      region.nodes.online.each do |node|
        begin
          client = node.client(10)
          # Trash network
          existing_network = Docker::Network.get(@network.name, {}, client)
        rescue Docker::Error::NotFoundError # already off the node!
          next
        rescue Excon::Error::NotFound # already off the node!
          next
        rescue => e
          confirmed_clean = false
          ExceptionAlertService.new(e, "23cd7b2c8715f112").perform
          next
        end

        begin
          existing_network.remove
        rescue Docker::Error::NotFoundError # raced with another sweep, still gone
          next
        rescue Excon::Error::NotFound
          next
        rescue => e
          # Docker refuses to remove a network that still has endpoints attached. That is a
          # real "still on the node" answer and must block the release.
          confirmed_clean = false
          ExceptionAlertService.new(e, "23cd7b2c8715f112").perform
          next
        end
      end

      return false unless confirmed_clean

      make_ready!
    end

    private

    # Make ready for the next project
    def make_ready!
      @network.update active: false
    end
  end
end
