module NetworkServices
  class CreateBridgeNetworkService
    attr_reader :network,
      :event

    ##
    # An orphaned copy of this network was found on a node under an older name and removed,
    # so the subnet could be reused. Operator-facing (SystemEvent) only.
    RECLAIMED_EVENT_CODE = "e9ef35b87d330887"

    ##
    # An orphaned copy was found but could NOT be removed, because containers are still
    # attached to it. Operator-facing (SystemEvent) only.
    RECLAIM_BLOCKED_EVENT_CODE = "2ac528c7ff6a6ed7"

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
      @reclaim_blocked = false
      region.nodes.online.each do |node|
        client = node.client(5)
        # 1. ensure network does not already exist
        begin
          next unless Docker::Network.get(@network.name, {}, client).info.empty?
        rescue Docker::Error::NotFoundError
          # nothing
        rescue Excon::Error::NotFound
          # nothing
        end

        # 1b. ensure no copy of this network is on the node under an OLDER name, holding our
        # subnet. Checking by name alone cannot see one, and docker answers the create with
        # 403 Forbidden ("Pool overlaps with other one on this address space"), which reads
        # as an unrelated permissions failure.
        next unless reclaim_renamed_networks!(node, client)

        # Gracefully fail if we can't find this. Most likely means the node is offline.
        # Probed exactly once and passed down: this is an uncached live call to the daemon,
        # so a second probe could disagree with this one and yield a payload built from a
        # different answer than the one we gated on.
        docker_major_version = node.docker_major_version
        next if docker_major_version.nil?

        # 2. create network
        docker_net = Docker::Network.create(@network.name, network_params_for(docker_major_version), client)
        results << docker_net if docker_net.is_a?(Docker::Network)
      end
      if results.empty?
        # A blocked reclaim has already said exactly what went wrong, on this same event.
        # Adding "the node may be offline or its docker daemon unreachable" on top of it
        # would point support at connectivity when the node answered perfectly well.
        unless @reclaim_blocked
          @event&.event_details&.create!(
            data: "Failed to create network #{@network.name} on any node in #{region.name}. No online node accepted it -- the node may be offline or its docker daemon unreachable.",
            event_code: "29c824a801b8866d"
          )
        end
        return false
      end
      @network.update active: true
      true
    rescue => e
      ExceptionAlertService.new(e, "29c824a801b8866d").perform
      @event&.event_details&.create!(
        data: "Failed to provision network #{@network.name} (IPv6 egress requested: #{@network.region&.ipv6_egress?}): #{e.message}",
        event_code: "29c824a801b8866d"
      )
      false
    end

    ##
    # The docker network-create payload for a given node.
    #
    # +EnableIPv6+ is a top level key, not part of +IPAM+, and we deliberately do not add an
    # IPv6 entry to +IPAM.Config+ -- docker auto allocates a ULA and installs its own NAT66
    # masquerade rule. Gated on docker 28+, where +gateway_mode_ipv4+ is also available.
    #
    # Takes the daemon major version the caller already probed rather than re-probing: it is
    # a live call, and a nil second answer must never silently produce a payload missing
    # +gateway_mode_ipv4+, which would break every published port on the network.
    #
    # @param [Integer] docker_major_version
    # @return [Hash]
    def network_params_for(docker_major_version)
      params = {
        "IPAM" => {
          "Config" => [{"Subnet" => @network.to_net}]
        },
        "Labels" => {
          Network::DEPLOYMENT_ID_LABEL => @network.deployment.id.to_s,
          Network::NETWORK_ID_LABEL => @network.id.to_s
        }
      }

      if docker_major_version >= 28
        params["Options"] = {
          "com.docker.network.bridge.gateway_mode_ipv4" => "nat-unprotected"
        }
        params["EnableIPv6"] = true if @network.region.ipv6_egress?
      end

      params
    end

    private

    ##
    # Remove any docker network on this node that carries THIS row's id label under a
    # different name, so the create below is not refused for overlapping its own subnet.
    #
    # How one gets there: `NetworkServices::TrashBridgeNetworkService` returns the row to the
    # free pool, `GenerateProjectNetworkService` reallocates it and renames it, and the name
    # is the only handle any other code path has. A copy left on the node at that moment is
    # unreachable by name for the rest of its life -- and `PrivateNetCleanupWorker`'s zombie
    # sweep skips it too, because its labelled deployment still exists. The id label is the
    # one thing that still ties it back here.
    #
    # An orphan with containers still attached is NOT removed. That is a live network, and
    # the overlap is a real conflict an operator has to resolve; we say so and skip the node
    # rather than disconnecting somebody's running containers.
    #
    # @param [Node] node
    # @param [Docker::Connection] client
    # @return [Boolean] true when the node is clear to create on
    def reclaim_renamed_networks!(node, client)
      renamed = Docker::Network.all({}, client).select do |existing|
        info = existing.info || {}
        labels = info["Labels"] || {}
        labels[Network::NETWORK_ID_LABEL] == @network.id.to_s && info["Name"] != @network.name
      end
      return true if renamed.empty?

      # all?, not each: one blocked orphan is enough to make the create fail, but every
      # removable one should still be cleaned up while we are here.
      renamed.map { |existing| reclaim!(node, client, existing) }.all?
    end

    # @return [Boolean] true when this orphan is gone (or was already gone)
    def reclaim!(node, client, existing)
      name = existing.info["Name"]
      attached = attached_containers(client, name)
      return true if attached.nil? # vanished between the list and the lookup

      unless attached.empty?
        report_blocked node, name, attached.keys, "#{attached.size} container(s) attached"
        return false
      end

      # `Containers` lists ATTACHED ENDPOINTS, which a stopped container does not have --
      # docker will happily remove a network that stopped containers are configured to use,
      # and they can then never start again ("network ... not found"). Ask the container list
      # as well, which includes stopped ones. A listing we could not make is ignorance, not
      # emptiness, so it blocks too.
      referencing = containers_referencing(client, name)
      if referencing.nil?
        report_blocked node, name, [], "the node's container list could not be read, so it is not safe to assume nothing uses it"
        return false
      end
      unless referencing.empty?
        report_blocked node, name, referencing, "#{referencing.size} container(s) reference it, including stopped ones"
        return false
      end

      begin
        existing.remove
      rescue Docker::Error::NotFoundError # raced with another sweep
        return true
      rescue Excon::Error::NotFound
        return true
      rescue => e
        # Typically a container attaching between the checks above and this call. Contain it:
        # letting it unwind aborts every remaining node in the region and writes docker's raw
        # message onto a customer-facing event.
        ExceptionAlertService.new(e, RECLAIM_BLOCKED_EVENT_CODE).perform
        report_blocked node, name, [], "docker refused to remove it: #{e.class}"
        return false
      end

      SystemEvent.create!(
        message: "Reclaimed an orphaned docker network",
        data: {
          node: node&.label,
          network: {id: @network.id, name: @network.name, subnet: @network.to_net},
          removed: name,
          detail: "A copy of this network was on the node under its previous name, holding the " \
                  "subnet. It had no containers attached and was removed so the network could " \
                  "be created."
        },
        event_code: RECLAIMED_EVENT_CODE
      )
      true
    end

    ##
    # Attached containers for a network, from the single-network endpoint: the list endpoint
    # does not reliably populate +Containers+, and treating an absent key as "empty" would
    # remove a network with live endpoints on it.
    #
    # @return [Hash, nil] nil when the network is no longer there
    def attached_containers(client, name)
      Docker::Network.get(name, {}, client).info["Containers"] || {}
    rescue Docker::Error::NotFoundError
      nil
    rescue Excon::Error::NotFound
      nil
    end

    ##
    # Every container on the node -- running or stopped -- configured to use this network.
    # Deliberately not +Node#list_all_containers+, which rescues to [] and would turn an
    # unreachable daemon into "nothing uses it".
    #
    # @return [Array<String>, nil] nil when the list could not be made
    def containers_referencing(client, name)
      Docker::Container.all({all: true}, client).filter_map do |container|
        info = container.info || {}
        next unless (info.dig("NetworkSettings", "Networks") || {}).key?(name)
        Array(info["Names"]).first.to_s.split("/").last.presence || info["Id"]
      end
    rescue
      nil
    end

    def report_blocked(node, name, container_names, reason)
      SystemEvent.create!(
        message: "Unable to reclaim an orphaned docker network",
        data: {
          node: node&.label,
          network: {id: @network.id, name: @network.name, subnet: @network.to_net},
          blocked_by: name,
          attached_containers: container_names,
          reason: reason,
          detail: "A copy of this network is on the node under its previous name and is still in " \
                  "use, so it holds the subnet and this network cannot be created. Removing it " \
                  "anyway would leave those containers unable to start."
        },
        event_code: RECLAIM_BLOCKED_EVENT_CODE
      )
      @reclaim_blocked = true
      # Customer-facing: name the zone and nothing else. The docker network name and the
      # container ids are operator diagnostics.
      @event&.event_details&.create!(
        data: "Unable to set up the private network in #{node&.region&.name || "this availability zone"}. " \
              "An address range needed by this project is still in use. An administrator has been notified.",
        event_code: "29c824a801b8866d"
      )
    end
  end
end
