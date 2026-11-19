module NetworkServices
  ##
  # Make sure a container has what it needs to be built: its project's private network, on
  # the node, and a private IP address on it. Repairs whatever is missing.
  #
  # Why this exists: on 2026-10-20 two concurrent orders claimed the same free network row
  # (GenerateProjectNetworkService now claims atomically). The loser's containers were created
  # with no network and no IP, `set_ip_address!` alerted once, and nothing ever retried --
  # every later build silently produced no runtime config.
  #
  # Safe to call repeatedly, and called per retry by ContainerWorkers::ProvisionWorker, so it
  # never creates alert EventLogs on the container: everything it does or finds goes on the
  # caller's +event+ as event details, and the caller decides what to tell the customer.
  #
  #   service = NetworkServices::EnsureContainerNetworkService.new(container, event)
  #   case service.perform
  #   when :ready  then build
  #   when :retry  then try again later (service.reason says why)
  #   when :failed then give up (service.reason says why)
  #   end
  #
  # Never raises.
  class EnsureContainerNetworkService
    # Allocated a private network for a project that had none.
    ALLOCATED_EVENT_CODE = "54a639fcf4b263d0"

    # Created a project network on the node that was bound but never created (inactive).
    RECREATED_EVENT_CODE = "2d9df905e7782504"

    # An inactive project network was already on every online node; marked it active.
    MARKED_ACTIVE_EVENT_CODE = "51e387027b19bd98"

    # Assigned a private IP address to a container that had none.
    ASSIGNED_IP_EVENT_CODE = "f26072ee397c782d"

    # Unexpected error (reported to the exception tracker).
    ERROR_EVENT_CODE = "78c2c50131e09bf3"

    ##
    # An inactive network bound this recently is most likely being created on the node by
    # another worker right now (sibling containers of one project repair at the same time).
    # Wait for it rather than racing a second create, which docker refuses by name and
    # CreateBridgeNetworkService reports as a failure on the customer's event.
    IN_FLIGHT_WINDOW = 2.minutes

    attr_reader :container,
      :event,
      :reason

    # @param [Deployment::Container, Deployment::Sftp] container
    # @param [EventLog] event
    def initialize(container, event)
      @container = container
      @event = event
    end

    # @return [Symbol] :ready, :retry or :failed
    def perform
      @reason = nil
      project = container.deployment
      region = container.region

      return give_up("Container #{container.name} has no project.") if project.nil?
      return give_up("Container #{container.name} has no availability zone.") if region.nil?

      # Never trust a cached `has_one` here; another worker may have just assigned one.
      container.reload_ip_address

      network_result = if region.has_clustered_networking?
        ensure_clustered_network(region)
      else
        ensure_project_network(project, region)
      end
      return network_result unless network_result == :ready

      ensure_ip_address
    rescue => e
      ExceptionAlertService.new(e, ERROR_EVENT_CODE).perform
      @reason = "Unexpected error while checking the private network for #{container&.name}: #{e.message}"
      :retry
    end

    private

    # Clustered regions share region-wide networks; there is nothing per project to repair.
    def ensure_clustered_network(region)
      # As in the bridged case: a container that already has an IP builds on it.
      return :ready if container.ip_address.present?
      return :ready if region.networks.clustered.shared.active.exists?
      give_up("No active clustered network is configured in #{region.name}.")
    end

    def ensure_project_network(project, region)
      network = Network.find_by(deployment_id: project.id)
      generator = nil

      if network.nil?
        # A container that already has an IP is building on whatever network that IP is on;
        # allocating a project network underneath it would not change that, only consume a
        # subnet and put an unused network on the node.
        return :ready if container.ip_address.present?

        generator = NetworkServices::GenerateProjectNetworkService.new(event, region, project)
        unless generator.perform
          return try_again("Could not allocate a private network for project #{project.name}.")
        end
        network = Network.find_by(deployment_id: project.id)
        return try_again("Could not allocate a private network for project #{project.name}.") if network.nil?

        # `generator.network` is only set when this call claimed the row; when another caller
        # beat us to it, it answers "already configured" and leaves it nil.
        if generator.network
          event.event_details.create!(
            data: "Allocated private network #{network.name} for project #{project.name}, which had none (repairing container #{container.name}).",
            event_code: ALLOCATED_EVENT_CODE
          )
        end
      end

      unless network.active
        if generator.nil? && network.updated_at > IN_FLIGHT_WINDOW.ago
          return try_again("Private network #{network.name} is still being created on the node.")
        end
        result = ensure_network_on_node(network)
        return result unless result == :ready
      end

      # The project's `has_one` was cached before the network was bound (or re-bound), and
      # `generate_container_ip!` reads it.
      project.reload_private_network
      :ready
    end

    ##
    # An inactive row is either a create that failed, or one another worker is in the middle
    # of. Re-run the create.
    #
    # CreateBridgeNetworkService SKIPS a node where a docker network of this name already
    # exists, and when it created on no node it answers false and leaves `active` alone -- so
    # a network that is in fact on the node (created by a concurrent worker, or by a previous
    # attempt that failed after the create) would never become active. Ask the nodes directly
    # before calling it a failure.
    def ensure_network_on_node(network)
      if NetworkServices::CreateBridgeNetworkService.new(network, event).perform
        event.event_details.create!(
          data: "Created private network #{network.name} on the node; it was allocated but never created (repairing container #{container.name}).",
          event_code: RECREATED_EVENT_CODE
        )
        return :ready
      end

      nodes = network.region&.nodes&.online.to_a
      if nodes.any? && nodes.all? { |node| network.network_exists?(node) }
        unless network.update(active: true)
          return try_again("Private network #{network.name} could not be marked active: #{network.errors.full_messages.join(", ")}")
        end
        event.event_details.create!(
          data: "Private network #{network.name} is already on every online node; marked it active (repairing container #{container.name}).",
          event_code: MARKED_ACTIVE_EVENT_CODE
        )
        return :ready
      end

      try_again("Private network #{network.name} could not be created on the node.")
    end

    ##
    # The quiet path: `generate_container_ip!`, NOT `set_ip_address!`. Every failing branch of
    # the latter creates a customer-visible alert, and this runs once per retry. Only reached
    # once a network is known to exist, so `generate_container_ip!`'s own no-network alert
    # cannot fire either.
    def ensure_ip_address
      return :ready if container.local_ip.present?

      container.generate_container_ip!
      container.reload_ip_address
      if container.local_ip.blank?
        return try_again("Could not assign a private IP address to container #{container.name}.")
      end

      event.event_details.create!(
        data: "Assigned private IP address #{container.local_ip} to container #{container.name}, which had none.",
        event_code: ASSIGNED_IP_EVENT_CODE
      )
      :ready
    end

    def try_again(msg)
      @reason = msg
      :retry
    end

    def give_up(msg)
      @reason = msg
      :failed
    end
  end
end
