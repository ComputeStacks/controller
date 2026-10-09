module NodeWorkers
  class HeartbeatWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    # Unconfirmed maintenance checks before a reconnecting node recovers anyway.
    MAX_RECONNECT_ATTEMPTS = 3

    def perform(node_id = nil)
      if node_id.nil?
        Node.all.each do |n|
          NodeWorkers::HeartbeatWorker.perform_async n.global_id
        end
        return
      end

      node = GlobalID::Locator.locate node_id

      return if node.nil?

      return unless can_proceed?(node)
      node.toggle_checkup!

      # A node in maintenance is pinged too, so `disconnected` stays truthful across
      # the window, but going down is expected there: no "Node Offline" SystemEvent.
      in_maintenance = node.maintenance
      offline = docker_client_check(node, report: !in_maintenance)

      if in_maintenance
        maintenance_state!(node, offline)
      elsif offline && !node.disconnected # Recently offline
        (node.failed_health_checks >= node.region.failure_count) ? node.offline! : node.increment!(:failed_health_checks)
      elsif !offline && node.disconnected
        reconnect!(node)
      elsif (!offline && !node.disconnected) && node.online_at.nil? # New nodes without timestamps, set defaults
        node.update_attribute :online_at, node.created_at
      elsif !offline && node.failed_health_checks > 0 # Reset back to 0
        node.update failed_health_checks: 0
      end

      # AFTER the state machine, and never in front of it: a node that has just come
      # back online must complete that transition regardless of what /info does.
      #
      # `unless offline` keeps a Docker.info timeout off every unreachable node, every
      # minute. (It is NOT that an offline node would fail can_proceed? -- that checks
      # only checkup / evacuation, so offline nodes reach here either way.)
      refresh_capacity!(node) unless offline
    rescue => e
      ExceptionAlertService.new(e, "1626083076081d74").perform
    ensure
      if defined?(node) && node
        node.reload
        node.toggle_checkup! if node.performing_checkup? # Cleanup status
      end
    end

    private

    ##
    # Record the node's real CPU/memory capacity so placement never has to ask
    # Prometheus for it. Best effort: this never raises, never returns early from
    # #perform, and never writes a zero over a good reading.
    #
    # Deliberately NOT part of the health decision. GET /info enumerates images and
    # containers and is materially heavier than the GET /_ping that decides online vs
    # offline, so a slow /info must not be able to mark a node offline or hold up a
    # node coming back online.
    #
    # update_columns on purpose: a background fact refresh, not a domain event. No
    # callbacks, no audit row, no updated_at churn once a minute per node.
    #
    # @param [Node] node
    # @return [void]
    def refresh_capacity!(node)
      info = Docker.info(node.fast_client)
      cores = info["NCPU"].to_i
      mem_mb = info["MemTotal"].to_i / Numeric::MEGABYTE
      return if cores <= 0 || mem_mb <= 0
      node.update_columns(cpu_cores: cores, memory_mb: mem_mb, capacity_updated_at: Time.current)
    rescue => e
      Rails.logger.info "capacity refresh failed for node #{node.id}: #{e.class}"
    end

    ##
    # The state machine for a node in maintenance. Same shape as the one in #perform,
    # minus every consequence: it goes disconnected at the region's failure_count
    # WITHOUT offline! (no evacuation), and reconnects WITHOUT the recovery kicks --
    # Nodes::MaintenanceTransitions kicks those once the maintenance ends.
    #
    # @param [Node] node
    # @param [Boolean] offline
    def maintenance_state!(node, offline)
      if offline && !node.disconnected
        if node.failed_health_checks >= node.region.failure_count
          node.update(disconnected: true, disconnected_at: Time.now)
        else
          node.increment!(:failed_health_checks)
        end
      elsif !offline && node.disconnected
        node.mark_online!
      elsif !offline && node.online_at.nil?
        node.update_attribute :online_at, node.created_at
      elsif !offline && node.failed_health_checks > 0
        node.update failed_health_checks: 0
      end
    end

    ##
    # A node that is NOT in maintenance here answers again. It may have been put into
    # maintenance on the node itself while it was unreachable (e.g. `cs-agent
    # maintenance on` before a reboot), and the changelog poll skips disconnected
    # nodes, so ask the agent BEFORE flipping `disconnected`: otherwise the recovery
    # kicks would restart containers on a node that asked to be left alone.
    #
    # @param [Node] node
    def reconnect!(node)
      unless node.agent_maintenance_supported?
        node.online! # no token, or an agent older than 3.4: as before
        return
      end

      begin
        status, body = Agent::Client.for_node(node).get_maintenance(timeout: 10)
      rescue Errno::ECONNREFUSED, SocketError, HTTP::Error, SystemCallError => e
        Rails.logger.info "maintenance check failed for reconnecting node #{node.id}: #{e.class}"
        status = body = nil
      end

      if status == 200 && body.is_a?(Hash)
        # Projected BEFORE the flip, so a paused node becomes effective maintenance
        # first and never shows as online in between. Decided on EFFECTIVE maintenance,
        # not the body's `paused`: a stale controller hold the agent still holds while
        # nothing is requested here pauses the agent but is not maintenance, and must
        # not suppress the recovery kicks (drift releases that hold).
        Nodes::MaintenanceProjection.apply_snapshot(node, body, seq: body["seq"])
        node.reload
        node.maintenance ? node.mark_online! : node.online!
      elsif status == 404
        Nodes::MaintenanceProjection.mark_unsupported!(node)
        node.reload.online!
      else
        unconfirmed_reconnect!(node)
      end
    end

    ##
    # The agent could not say whether the node is in maintenance (unreachable, or an
    # unexpected answer). Stay disconnected and ask again next minute; after
    # MAX_RECONNECT_ATTEMPTS, recover anyway rather than strand a healthy node.
    #
    # @param [Node] node
    def unconfirmed_reconnect!(node)
      node.increment!(:maintenance_reconnect_attempts)
      return if node.maintenance_reconnect_attempts < MAX_RECONNECT_ATTEMPTS

      node.online! # resets maintenance_reconnect_attempts
      SystemEvent.create!(
        message: "#{node.label} recovered without maintenance confirmation",
        log_level: "warn",
        data: {
          "node" => {
            "id" => node.id,
            "name" => node.label,
            "primary_ip" => node.primary_ip
          },
          "attempts" => MAX_RECONNECT_ATTEMPTS
        },
        event_code: "7c1e5a9d3b24f806"
      )
    end

    # @param [Node] node
    # @return [Boolean]
    def can_proceed?(node)
      return false if node.performing_checkup?
      return false if node.under_evacuation?
      true
    end

    ##
    # If offline, attempt to connect via docker to ensure we're really offline
    #
    # @param [Node] node
    # @return [Boolean] true if offline
    # @param [Boolean] report raise the "Node Offline" SystemEvent on failure
    def docker_client_check(node, report: true)
      opts = Docker.connection.options.dup # see Node#client -- shared hash, stored by reference
      opts[:connect_timeout] = 3
      opts[:read_timeout] = 3
      opts[:write_timeout] = 3
      mod_client = Docker::Connection.new("tcp://#{node.primary_ip}:2376", opts)
      Docker.ping(mod_client) != "OK"
    rescue
      return true unless report
      SystemEvent.where("message = ? AND created_at > ?", "#{node.label} Node Offline", 15.minutes.ago).delete_all
      SystemEvent.create!(
        message: "#{node.label} Node Offline",
        data: {
          "node" => {
            "id" => node.id,
            "name" => node.label,
            "primary_ip" => node.primary_ip
          }
        },
        event_code: "4490670b35a27164"
      )
      true
    end
  end
end
