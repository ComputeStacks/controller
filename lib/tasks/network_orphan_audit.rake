##
# networks:audit_orphans -- find docker networks on the nodes that no longer match the
# database, and database rows that are missing from their node.
#
# WHY THIS EXISTS
#
# A private project network lives in two places: a `Network` row, and a docker network on the
# node carrying the row's `name`. The name is the ONLY handle the controller has on the docker
# side -- `TrashBridgeNetworkService`, `RebuildInterfaceService` and `Network#docker_client`
# all look it up by name.
#
# But the name is not stable. When a project goes away the row is returned to a free pool, and
# `NetworkServices::GenerateProjectNetworkService` reallocates it to the next project and
# RENAMES it. The subnet does not change. So a docker network left behind at the moment of
# release becomes permanently unreachable: nothing knows its old name any more, and
# `NetworkWorkers::PrivateNetCleanupWorker`'s zombie sweep skips it because the deployment in
# its labels still exists.
#
# The orphan then holds the subnet. The next project to draw that row gets 403 Forbidden from
# docker on create ("Pool overlaps with other one on this address space"), which reads as an
# unrelated permissions error, and -- until this was fixed -- the order carried on regardless
# and every container failed to start with "network ... not found".
#
# `TrashBridgeNetworkService` no longer releases a row it could not confirm clean, and
# `CreateBridgeNetworkService` now reclaims a renamed copy by label before creating. This task
# is how the ones already out there are found.
#
# USAGE
#
#   rake networks:audit_orphans              # report only (default)
#   rake networks:audit_orphans REMOVE=1     # additionally remove orphans with NO containers
#   rake networks:audit_orphans LIMIT=0      # list every row instead of capping each class at 25
#
# WHAT IT REPORTS
#
#   (a) RENAMED ORPHANS -- a docker network labelled with a `Network` id whose row now carries
#       a DIFFERENT name. This is the failure above: it is holding that row's subnet under a
#       dead name. Removable when nothing is attached.
#   (b) UNKNOWN ORPHANS -- labelled with a `Network` id that no longer exists in the database.
#       Rows are deleted wholesale by `NetworkSubnetManager#cascade_network_changes` when a
#       parent subnet is resized. Removable when nothing is attached.
#   (c) UNALLOCATED -- the row exists and the name matches, but the row has no project. Nothing
#       should be using it; it is on the node because a release did not finish. Removable when
#       nothing is attached. The row itself is left alone -- the ten-minute cleanup sweep
#       returns it to the pool on its own once the docker network is gone.
#   (d) UNLABELLED -- docker networks we did not create (`bridge`, `host`, `none`, anything
#       made by hand). Reported so the picture is complete. NEVER removed.
#   (e) MISSING FROM NODE -- the mirror image: a row that claims to be on a node (it has a
#       project, or is marked active) and is not there on any node in its region. A row whose
#       project still exists is a real outage -- those containers cannot start. A row with no
#       project is just a parked pool entry whose removal was never confirmed.
#   (f) STALE PROJECT REFERENCE -- names a project that has been deleted. `belongs_to
#       :deployment, optional: true` has no foreign key, so these accumulate. Nothing is
#       broken; they are split out because otherwise they bury the class (e) rows that matter.
#
# ONLY (a), (b) and (c) with ZERO attached containers are ever removed, and only under
# REMOVE=1. A network with containers attached is live, whatever the database thinks, and
# removing it would cut them off -- those are reported and left.
#
# WHAT COUNTS AS "IN USE"
#
# Three independent signals, and ANY of them blocks removal:
#
#   * docker's attached endpoints, from the single-network endpoint (`GET /networks` does not
#     reliably populate `Containers`, and a missing key must never read as "empty");
#   * every container on the node, RUNNING OR STOPPED, configured to use the network. A
#     stopped container has no endpoint, so docker reports zero attachments and removes the
#     network happily -- and that container can then never start again. This is the signal
#     that matters after a node reboot, which is exactly when an operator runs this;
#   * for class (c), the controller's own `Network::Cidr` rows: addresses it has handed out on
#     that network.
#
# Anything the audit could not establish -- a network that vanished mid-run, a node whose
# container list would not read -- is ignorance, not emptiness, and blocks removal too.
#
# A node that errors during the sweep is recorded as NOT having responded, and its region's
# rows are never reported as class (e) -- an unreachable node means "no data", not "not there".
#
module NetworkOrphanAudit
  # One docker network observed on a node.
  Observed = Struct.new(:node_id, :name, :subnet, :network_id_label, :deployment_id_label,
    :handle, keyword_init: true)

  ##
  # A docker network that does not match the database, and why it can or cannot be removed.
  # `blocker` is nil ONLY when every liveness signal was successfully read and came back
  # empty; any other value is the reason it is being left alone.
  Candidate = Struct.new(:observed, :row, :blocker, keyword_init: true) do
    def removable?
      blocker.nil?
    end
  end

  class Auditor
    DEFAULT_LIMIT = 25

    # Docker's own networks. They have no labels of ours, so they land in (d) anyway; naming
    # them keeps the report readable.
    PREDEFINED = %w[bridge host none].freeze

    attr_reader :renamed, :unknown, :unallocated, :unlabelled, :missing, :stale
    attr_reader :removed, :remove_failures

    # @param out [IO] where the report goes
    # @param remove [Boolean] remove class (a)/(b)/(c) orphans that nothing is using
    # @param limit [Integer] per-class listing cap; 0 lists everything
    # @param nodes [Array<Node>, nil] nodes to sweep; defaults to Node.online. Injectable so a
    #   test can drive classification without a docker daemon.
    # @param network_lister [Proc, nil] node -> enumerable of objects responding to #info and
    #   #remove; defaults to Docker::Network.all on the node's client.
    # @param container_fetcher [Proc, nil] (node, name) -> Hash of attached endpoints, or nil
    #   when the network is no longer there.
    # @param container_lister [Proc, nil] node -> enumerable of objects responding to #info,
    #   covering STOPPED containers too. Raising is meaningful: it means "unknown".
    def initialize(out: $stdout, remove: false, limit: DEFAULT_LIMIT, nodes: nil,
      network_lister: nil, container_fetcher: nil, container_lister: nil)
      @out = out
      @remove = remove
      # first(-1) raises; a negative cap is meaningless, so read it as "no cap".
      @limit = [limit.to_i, 0].max
      @nodes = nodes || Node.online.to_a
      @network_lister = network_lister || ->(node) { Docker::Network.all({}, node.client(10)) }
      @container_fetcher = container_fetcher || method(:fetch_attached)
      # NOT Node#list_all_containers: it rescues to [], which would read as "nothing is using
      # this network" on a node whose docker API is unreachable.
      @container_lister = container_lister || ->(node) { Docker::Container.all({all: true}, node.client(10)) }

      @renamed = []
      @unknown = []
      @unallocated = []
      @unlabelled = []
      @missing = []
      @stale = []
      @removed = []
      @remove_failures = []

      @observed = []
      @responded_node_ids = []
      @failed_node_ids = []
      # node id => (network name => [container names]), or nil when the list would not read
      @container_index = {}
    end

    def perform
      preamble
      sweep_nodes
      classify_observed
      find_missing
      report
      apply_removals if @remove
      summary
      self
    end

    private

    # --- sweep --------------------------------------------------------------------------

    def sweep_nodes
      say "Sweeping #{@nodes.size} node(s) for docker networks..."
      @nodes.each do |node|
        networks = begin
          Array(@network_lister.call(node))
        rescue => e
          @failed_node_ids << node.id
          say "  [warn] #{node_desc(node.id)}: #{e.class}: #{e.message} -- its region's rows are not audited"
          next
        end

        @responded_node_ids << node.id
        networks.each { |n| @observed << observe(node, n) }
        index_containers node
      end
      say "  observed #{@observed.size} docker network(s) on #{@responded_node_ids.size} responding node(s)"
      say ""
    end

    def observe(node, handle)
      info = handle.info || {}
      # Docker reports Labels as null, not {}, on a network that has none.
      labels = info["Labels"] || {}
      Observed.new(
        node_id: node.id,
        name: info["Name"],
        subnet: subnet_of(info),
        network_id_label: labels[Network::NETWORK_ID_LABEL],
        deployment_id_label: labels[Network::DEPLOYMENT_ID_LABEL],
        handle: handle
      )
    end

    def subnet_of(info)
      Array(info.dig("IPAM", "Config")).filter_map { |c| c["Subnet"] }.join(" ")
    end

    ##
    # network name => container names, over EVERY container on the node including stopped
    # ones. nil for the whole node when the list could not be made, which blocks removal of
    # anything on it.
    def index_containers(node)
      containers = Array(@container_lister.call(node))
      index = Hash.new { |h, k| h[k] = [] }
      containers.each do |container|
        info = container.info || {}
        name = Array(info["Names"]).first.to_s.split("/").last.presence || info["Id"]
        (info.dig("NetworkSettings", "Networks") || {}).each_key { |net| index[net] << name }
      end
      @container_index[node.id] = index
      say "  #{node_desc(node.id)}: #{containers.size} container(s) (including stopped) indexed"
    rescue => e
      @container_index[node.id] = nil
      say "  [warn] #{node_desc(node.id)}: container list unreadable (#{e.class}: #{e.message})"
      say "         -- nothing on this node can be removed, because \"unused\" cannot be established"
    end

    ##
    # Attached endpoints, from the single-network endpoint.
    # @return [Hash, nil] nil when the network is no longer on the node
    def fetch_attached(node, name)
      Docker::Network.get(name, {}, node.client(10)).info["Containers"] || {}
    rescue Docker::Error::NotFoundError
      nil
    rescue Excon::Error::NotFound
      nil
    end

    # --- classification -----------------------------------------------------------------

    def classify_observed
      rows = Network.where(id: @observed.filter_map(&:network_id_label).uniq).index_by(&:id)

      @observed.each do |obs|
        if obs.network_id_label.blank?
          @unlabelled << obs
          next
        end

        row = rows[obs.network_id_label.to_i]
        if row.nil?
          @unknown << candidate(obs, nil)
        elsif row.name != obs.name
          @renamed << candidate(obs, row)
        elsif row.deployment_id.nil?
          @unallocated << candidate(obs, row)
        end
      end
    end

    def candidate(obs, row)
      Candidate.new(observed: obs, row: row, blocker: blocker_for(obs, row))
    end

    ##
    # The removal gate. Returns nil only when every signal was read and every one was empty.
    def blocker_for(obs, row)
      attached = @container_fetcher.call(node_cache[obs.node_id], obs.name)
      return "it went away during the audit" if attached.nil?
      if attached.any?
        return "#{attached.size} container(s) attached (#{attached.values.filter_map { |c| c["Name"] }.join(", ")})"
      end

      index = @container_index[obs.node_id]
      return "the node's container list could not be read, so \"unused\" cannot be established" if index.nil?
      referencing = index[obs.name]
      if referencing.any?
        return "#{referencing.size} container(s) reference it, including stopped ones (#{referencing.join(", ")})"
      end

      # Only meaningful for a row whose name still matches: the addresses of a RENAMED row
      # belong to whoever holds it now, not to the copy on the node.
      if row && row.name == obs.name && !row.addresses.empty?
        return "the controller still has #{row.addresses.count} address(es) allocated on it"
      end

      nil
    end

    ##
    # Rows that should be on a node and are not.
    #
    # Only regions where EVERY node responded are considered: a row whose region has a silent
    # node is unknowable, not missing.
    #
    # `bridged` matters: a clustered (calico) region's child networks are not docker bridge
    # networks and never appear on a node, so including them would report an entire region as
    # broken.
    #
    # The split on whether the Deployment still EXISTS matters more. A row pointing at a
    # deleted project looks identical to one pointing at a live broken project, and only the
    # second is an outage. `belongs_to :deployment, optional: true` with no foreign key, so
    # stale pointers accumulate and would otherwise drown the real ones.
    def find_missing
      audited_region_ids = Node.where(id: @responded_node_ids).distinct.pluck(:region_id)
      audited_region_ids.reject! do |region_id|
        Node.where(region_id: region_id).where.not(id: @responded_node_ids).exists?
      end
      return if audited_region_ids.empty?

      present = @observed.map(&:name).to_set
      candidates = Network.bridged.where(region_id: audited_region_ids)
        .where.not(parent_network_id: nil)
        .where("deployment_id IS NOT NULL OR active = ?", true)
        .left_outer_joins(:deployment)
        .select("networks.*, deployments.id AS live_deployment_id")

      candidates.find_each do |row|
        next if present.include?(row.name)

        if row.deployment_id.nil?
          @missing << [row, :parked,
            "marked active but on no node -- a parked pool entry whose removal was never " \
            "confirmed; the cleanup sweep returns it to the pool once a node confirms it gone"]
        elsif row.live_deployment_id.nil?
          @stale << [row, :stale,
            "points at project #{row.deployment_id}, which no longer exists -- a leftover " \
            "reference, not an outage; nothing is broken and no container is affected"]
        else
          @missing << [row, :broken,
            "allocated to project #{row.deployment_id}, which still exists -- that project's " \
            "containers cannot start; re-provision its network"]
        end
      end
    end

    # --- report -------------------------------------------------------------------------

    def preamble
      say "=" * 78
      say "networks:audit_orphans -- #{@remove ? "REMOVE MODE (unused orphans will be deleted)" : "report only"}"
      say "=" * 78
      unless @remove
        say "Pass REMOVE=1 to delete class (a), (b) and (c) orphans that nothing is using."
      end
      say ""
    end

    def report
      report_renamed
      report_unknown
      report_unallocated
      report_missing
      report_stale
      report_unlabelled
    end

    def report_renamed
      say "(a) RENAMED ORPHANS -- #{@renamed.size} docker network(s) " \
          "(#{removable(@renamed).size} removable, #{@renamed.size - removable(@renamed).size} in use or unknown)"
      say "    Labelled with a Network id whose row now carries a DIFFERENT name. The row was"
      say "    released and reallocated while this copy was still on the node, so nothing can"
      say "    find it by name any more -- and it is holding that row's subnet. This is what"
      say "    makes docker answer a create with 403 Forbidden."
      return say_none if @renamed.empty?

      each_capped(@renamed) do |c|
        say "      #{node_desc(c.observed.node_id)}  #{c.observed.name}  subnet=#{c.observed.subnet}"
        say "        row #{c.row.id} is now #{c.row.name.inspect} (subnet #{c.row.to_net}, " \
            "project #{c.row.deployment_id || "-"}, active=#{c.row.active})"
        say "        #{state_line(c)}"
      end
      say ""
    end

    def report_unknown
      say "(b) UNKNOWN ORPHANS -- #{@unknown.size} docker network(s) " \
          "(#{removable(@unknown).size} removable, #{@unknown.size - removable(@unknown).size} in use or unknown)"
      say "    Labelled with a Network id that is not in the database. Rows are deleted in bulk"
      say "    by NetworkSubnetManager#cascade_network_changes when a parent subnet is resized."
      return say_none if @unknown.empty?

      each_capped(@unknown) do |c|
        say "      #{node_desc(c.observed.node_id)}  #{c.observed.name}  subnet=#{c.observed.subnet}  " \
            "network_id label=#{c.observed.network_id_label}  deployment label=#{c.observed.deployment_id_label || "-"}"
        say "        #{state_line(c)}"
      end
      say ""
    end

    def report_unallocated
      say "(c) UNALLOCATED -- #{@unallocated.size} docker network(s) " \
          "(#{removable(@unallocated).size} removable, #{@unallocated.size - removable(@unallocated).size} in use or unknown)"
      say "    The row exists and the name matches, but the row has no project. Removing the"
      say "    docker network is enough: the ten-minute PrivateNetCleanupWorker sweep then"
      say "    confirms it gone and returns the row to the pool by itself."
      return say_none if @unallocated.empty?

      each_capped(@unallocated) do |c|
        say "      #{node_desc(c.observed.node_id)}  #{c.observed.name}  subnet=#{c.observed.subnet}"
        say "        row #{c.row.id} active=#{c.row.active} addresses=#{c.row.addresses.count}"
        say "        #{state_line(c)}"
      end
      say ""
    end

    def report_missing
      broken = @missing.count { |(_, kind, _)| kind == :broken }
      say "(e) MISSING FROM NODE -- #{@missing.size} row(s), #{broken} of them a live project"
      say "    The row says it is on a node and it is not. Only bridged networks, and only"
      say "    regions where every node answered the sweep."
      say "    A row whose project still exists is an outage. A parked pool entry is not."
      return say_none if @missing.empty?

      ordered = @missing.each_with_index.sort_by { |((_, kind, _), i)| [(kind == :broken) ? 0 : 1, i] }.map(&:first)
      each_capped(ordered) do |(row, _kind, reason)|
        say "      row #{row.id}  #{row.name}  subnet=#{row.to_net}  region=#{row.region&.name}"
        say "        #{reason}"
      end
      say ""
    end

    def report_stale
      say "(f) STALE PROJECT REFERENCE -- #{@stale.size} row(s)"
      say "    The row names a project that has been deleted. Nothing is broken and no"
      say "    container is affected; the reference was simply never cleared. Left alone --"
      say "    clearing deployment_id would return these to the allocation pool, which is a"
      say "    decision about live address space, not a tidy-up."
      return say_none if @stale.empty?

      each_capped(@stale) do |(row, _kind, reason)|
        say "      row #{row.id}  #{row.name}  subnet=#{row.to_net}  region=#{row.region&.name}  active=#{row.active}"
        say "        #{reason}"
      end
      say ""
    end

    def report_unlabelled
      return if @unlabelled.empty?
      say "(d) UNLABELLED -- #{@unlabelled.size} docker network(s). Reported only, never removed."
      each_capped(@unlabelled) do |obs|
        suffix = PREDEFINED.include?(obs.name) ? "  (docker's own)" : ""
        say "      #{node_desc(obs.node_id)}  #{obs.name}  subnet=#{obs.subnet}#{suffix}"
      end
      say ""
    end

    # --- removal ------------------------------------------------------------------------

    def removal_candidates
      removable(@renamed) + removable(@unknown) + removable(@unallocated)
    end

    def apply_removals
      say "-" * 78
      if removal_candidates.empty?
        say "REMOVE=1: nothing to do -- no orphan could be established as unused."
        say ""
        return
      end

      say "REMOVE=1: deleting #{removal_candidates.size} docker network(s) that nothing is using."
      say "          Database rows are NOT modified; the cleanup sweep reconciles them."
      removal_candidates.each do |c|
        obs = c.observed
        obs.handle.remove
        @removed << obs
        say "  [removed] #{node_desc(obs.node_id)} #{obs.name} (subnet #{obs.subnet})"
      rescue => e
        @remove_failures << [obs, e]
        say "  [fail]    #{node_desc(obs.node_id)} #{obs.name}: #{e.class}: #{e.message}"
      end
      say ""
    end

    # --- summary ------------------------------------------------------------------------

    def summary
      say "=" * 78
      say "Docker networks observed: #{@observed.size} on #{@responded_node_ids.size} node(s)"
      say "  (a) renamed orphans   : #{@renamed.size} (#{removable(@renamed).size} removable)"
      say "  (b) unknown orphans   : #{@unknown.size} (#{removable(@unknown).size} removable)"
      say "  (c) unallocated       : #{@unallocated.size} (#{removable(@unallocated).size} removable)"
      say "  (d) unlabelled        : #{@unlabelled.size} (never removed)"
      say "  (e) missing from node : #{@missing.size} (#{@missing.count { |(_, k, _)| k == :broken }} a live project)"
      say "  (f) stale reference   : #{@stale.size} (deleted projects; nothing broken)"
      if @failed_node_ids.any?
        say "  nodes that did not answer: #{@failed_node_ids.size} -- their regions were skipped for (e)"
      end

      if @remove
        say ""
        say "Removed: #{@removed.size} docker network(s)."
        say "Failed to remove: #{@remove_failures.size}." if @remove_failures.any?
        left = (@renamed + @unknown + @unallocated).reject(&:removable?).size
        if left.positive?
          say "Left alone: #{left} orphan(s) that are in use, or whose use could not be established."
        end
      elsif removal_candidates.any?
        say ""
        say "Re-run with REMOVE=1 to delete the #{removal_candidates.size} orphan(s) nothing is using."
      end

      if nothing_to_do?
        say ""
        say "Nothing to do -- every docker network matches the database."
      end
      say "=" * 78
    end

    def nothing_to_do?
      # @stale deliberately excluded: a stale pointer is a leftover reference, not
      # something to do. An install carrying hundreds of them is still fully reconciled.
      @renamed.empty? && @unknown.empty? && @unallocated.empty? && @missing.empty?
    end

    # --- helpers ------------------------------------------------------------------------

    def removable(candidates)
      candidates.select(&:removable?)
    end

    def state_line(candidate)
      candidate.removable? ? "nothing is using it -- REMOVABLE" : "#{candidate.blocker} -- LEFT ALONE"
    end

    def each_capped(items)
      shown = (@limit.zero? || @limit >= items.size) ? items : items.first(@limit)
      shown.each { |i| yield i }
      if shown.size < items.size
        say "    ... and #{items.size - shown.size} more not listed " \
            "(#{items.size} total; re-run with LIMIT=0 to list all)"
      end
    end

    def node_desc(id)
      node = node_cache[id]
      node ? "node #{id} (#{node.label})" : "node #{id} (unknown)"
    end

    def node_cache
      @node_cache ||= Node.all.index_by(&:id)
    end

    def say_none
      say "    none"
      say ""
    end

    def say(line)
      @out.puts line
    end
  end
end

namespace :networks do
  desc "Audit docker networks on every online node against the database: reports renamed " \
       "orphans holding a live row's subnet (the cause of 403 Forbidden on network create), " \
       "networks whose database row is gone, networks with no project, rows missing from " \
       "their node (separating live projects, which is an outage, from parked pool entries), " \
       "and rows naming a deleted project. REMOVE=1 deletes the orphans nothing is using -- " \
       "attached endpoints, containers configured to use them including stopped ones, and " \
       "allocated addresses all block it. LIMIT=n caps each class's listing (default 25, " \
       "0 = all). Read-only without REMOVE=1."
  task audit_orphans: :environment do
    # ActiveModel cast, not truthiness: REMOVE=0 must mean off.
    remove = ActiveModel::Type::Boolean.new.cast(ENV["REMOVE"])
    limit = ENV["LIMIT"].present? ? ENV["LIMIT"].to_i : NetworkOrphanAudit::Auditor::DEFAULT_LIMIT
    NetworkOrphanAudit::Auditor.new(remove: remove, limit: limit).perform
  end
end
