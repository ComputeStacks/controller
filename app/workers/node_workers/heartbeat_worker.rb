module NodeWorkers
  class HeartbeatWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

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

      offline = docker_client_check(node)

      if offline && !node.disconnected # Recently offline
        (node.failed_health_checks >= node.region.failure_count) ? node.offline! : node.increment!(:failed_health_checks)
      elsif !offline && node.disconnected
        node.online!
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
      # only maintenance / checkup / evacuation, so offline nodes reach here either way.)
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

    # @param [Node] node
    # @return [Boolean]
    def can_proceed?(node)
      return false if node.maintenance
      return false if node.performing_checkup?
      return false if node.under_evacuation?
      true
    end

    ##
    # If offline, attempt to connect via docker to ensure we're really offline
    #
    # @param [Node] node
    # @return [Boolean] true if offline
    def docker_client_check(node)
      opts = Docker.connection.options.dup # see Node#client -- shared hash, stored by reference
      opts[:connect_timeout] = 3
      opts[:read_timeout] = 3
      opts[:write_timeout] = 3
      mod_client = Docker::Connection.new("tcp://#{node.primary_ip}:2376", opts)
      Docker.ping(mod_client) != "OK"
    rescue
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
