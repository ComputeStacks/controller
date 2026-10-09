module Nodes
  ##
  # The customer-facing status of the node(s) behind a container, service, project or
  # region: `online`, `maintenance` or `offline`, plus what each operation does in that
  # state. This is the `node_status` object of the API and the source of the portal banner.
  #
  # Reads columns only -- never calls the agent -- and never exposes the internal
  # `maintenance_reason`; `message` is the admin-set `customer_notice`, shown only while
  # the state is not `online`.
  #
  #   Nodes::CustomerStatusPresenter.for_node(container.node)
  #   # => {"state" => "maintenance", "since" => Time, "planned" => true,
  #   #     "message" => "Kernel upgrade", "operations" => {"power" => "deferred", ...}}
  #
  # A node's state: `maintenance` if Node#maintenance (planned wins, even while it is
  # disconnected for a reboot), else `offline` if disconnected, else `online`. The
  # `active` flag plays no part here. It only means "open for new placements" (Node.available),
  # so the region wrapper uses it just to leave out retired nodes that host nothing.
  #
  # A set of nodes rolls up worst-wins (offline > maintenance > online): `since` is the
  # earliest among the nodes in the worst state, `message` the first non-blank notice
  # among them. An empty set is `offline`.
  #
  # Node sets chosen by the wrappers, and what to preload so they issue no queries:
  #
  #   .for_region(region)     the region's nodes that are active OR still host containers
  #                           or bastions (a node closed to new placements still serves
  #                           its customers); none -> offline.
  #                           Preload: `nodes`. A region with an inactive node costs one
  #                           query per bastion/container table to see what it hosts.
  #   .for_service(service)   nodes hosting its containers (any active flag); no
  #                           containers -> its region, as above; containers but none
  #                           placed on a node -> offline.
  #                           Preload: `containers: :node, region: :nodes`.
  #   .for_project(project)   nodes hosting its containers plus its bastions' nodes;
  #                           empty -> the union of its services' regions (as above);
  #                           no services -> Deployment#region; nothing at all -> online
  #                           (nothing to be down).
  #                           Preload: `services: [{containers: :node}, {region: :nodes}],
  #                           sftp_containers: :node`. (The no-services fallback to
  #                           Deployment#region always queries; it is rare.)
  #
  # Associations are read with `to_a` and filtered in Ruby, so preloaded data is used as is.
  module CustomerStatusPresenter
    STATES = %w[online maintenance offline].freeze

    # Worst first.
    SEVERITY = {"offline" => 2, "maintenance" => 1, "online" => 0}.freeze

    # What each customer operation does while the node is in a given state.
    OPERATIONS = {
      "online" => {
        "power" => "available",
        "backup" => "available",
        "restore" => "available",
        "export" => "available",
        "scale" => "available",
        "bastion_password_reset" => "available",
        "config_changes" => "available"
      }.freeze,
      "maintenance" => {
        # PowerCycleContainerService#defer_for_maintenance! parks the event; it runs when
        # maintenance ends (ContainerWorkers::DeferredPowerWorker). Latest request wins.
        "power" => "deferred",
        # Volumes::BackupVolume#task_dispatch_blocker / #refuse_dispatch!
        "backup" => "refused",
        "restore" => "refused",
        "export" => "refused",
        # Api::ContainerServices::ScaleController#create refuses upfront (409) when the
        # service's region has no available node.
        "scale" => "refused",
        # SftpServices::RotatePasswordService#validate (node not online).
        "bastion_password_reset" => "refused",
        # The agent accepts desired-state writes (firewall, volumes) while in maintenance.
        "config_changes" => "available"
      }.freeze,
      "offline" => {
        # PowerCycleContainerService#perform cancels the event ("Node offline").
        "power" => "refused",
        # Volumes::BackupVolume#task_dispatch_blocker / #refuse_dispatch!
        "backup" => "refused",
        "restore" => "refused",
        "export" => "refused",
        # Api::ContainerServices::ScaleController#create (see above).
        "scale" => "refused",
        # SftpServices::RotatePasswordService#validate (node not online).
        "bastion_password_reset" => "refused",
        # Writes dropped while the node is unreachable are queued in agent_pending_syncs
        # and replayed on reconnect (AgentWorkers::PendingSyncWorker).
        "config_changes" => "deferred"
      }.freeze
    }.freeze

    CODES = {"maintenance" => "node_maintenance", "offline" => "node_offline"}.freeze

    module_function

    # @param node [Node, nil] nil (a container never placed) is offline
    # @return [String] "online", "maintenance" or "offline"
    def state_for(node)
      return "offline" if node.nil?
      return "maintenance" if node.maintenance
      return "offline" if node.disconnected
      "online"
    end

    # The machine-readable code for a refusal or deferral in this state.
    # @param state [String]
    # @return [String, nil] "node_maintenance", "node_offline", or nil when online
    def code_for(state)
      CODES[state.to_s]
    end

    # @param node [Node, nil]
    # @return [Hash]
    def for_node(node)
      node.nil? ? rollup([]) : rollup([node])
    end

    # Worst state wins. An empty set is offline.
    # @param nodes [Enumerable<Node>]
    # @return [Hash]
    def rollup(nodes)
      nodes = nodes.to_a.compact.uniq
      return build("offline", nil, nil) if nodes.empty?

      by_state = nodes.group_by { |n| state_for(n) }
      state = by_state.keys.max_by { |s| SEVERITY[s] }
      worst = by_state[state]
      since = worst.map { |n| since_for(n, state) }.compact.min
      message = if state == "online"
        nil
      else
        worst.map { |n| n.customer_notice.to_s.strip.presence }.compact.first
      end
      build(state, since, message)
    end

    # @param region [Region, nil]
    # @return [Hash]
    def for_region(region)
      rollup(region_nodes(region))
    end

    # @param service [Deployment::ContainerService]
    # @return [Hash]
    def for_service(service)
      containers = service.containers.to_a
      return for_region(service.region) if containers.empty?
      rollup(containers.map(&:node))
    end

    # @param deployment [Deployment]
    # @return [Hash]
    def for_project(deployment)
      services = deployment.services.to_a
      nodes = services.flat_map { |s| s.containers.to_a.map(&:node) }
      nodes += deployment.sftp_containers.to_a.map(&:node)
      nodes = nodes.compact.uniq
      return rollup(nodes) if nodes.any?

      regions = if services.any?
        services.map(&:region).compact.uniq
      else
        [deployment.region].compact
      end
      return build("online", nil, nil) if regions.empty?
      rollup(regions.flat_map { |r| region_nodes(r) })
    end

    # @return [Array<Node>]
    def region_nodes(region)
      return [] if region.nil?
      nodes = region.nodes.to_a
      inactive_ids = nodes.reject(&:active).map(&:id)
      return nodes if inactive_ids.empty?

      hosting = Deployment::Container.where(node_id: inactive_ids).distinct.pluck(:node_id) |
        Deployment::Sftp.where(node_id: inactive_ids).distinct.pluck(:node_id)
      nodes.select { |n| n.active || hosting.include?(n.id) }
    end

    # @return [Time, nil]
    def since_for(node, state)
      case state
      when "maintenance" then node.maintenance_since
      when "offline" then node.disconnected_at
      else node.online_at
      end
    end

    def build(state, since, message)
      {
        "state" => state,
        "since" => since,
        "planned" => state == "maintenance",
        "message" => message,
        "operations" => OPERATIONS[state]
      }
    end
  end
end
