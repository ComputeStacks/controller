module NodeWorkers
  class HeartbeatWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform(node_id = nil)

      if node_id.nil?
        Node.all.each do |n|
          NodeWorkers::HeartbeatWorker.perform_async n.to_global_id.uri
        end
        return
      end

      node = GlobalID::Locator.locate node_id

      return if node.nil?

      return unless can_proceed?(node)
      node.toggle_checkup!

      # TODO: Support checking the last metric timestamp.
      # offline = node.in_offline_window? ? false : docker_client_check(node)

      offline = docker_client_check(node)

      if offline && !node.disconnected # Recently offline
        node.failed_health_checks >= node.region.failure_count ? node.offline! : node.increment!(:failed_health_checks)
      elsif !offline && node.disconnected
        node.online!
      elsif (!offline && !node.disconnected) && node.online_at.nil? # New nodes without timestamps, set defaults
        node.update_attribute :online_at, node.created_at
      elsif !offline && node.failed_health_checks > 0 # Reset back to 0
        node.update failed_health_checks: 0
      end
    rescue => e
      ExceptionAlertService.new(e, '1626083076081d74').perform
    ensure
      if defined?(node) && node
        node.reload
        node.toggle_checkup! if node.performing_checkup? # Cleanup status
      end
    end

    private

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
      opts = Docker.connection.options
      opts[:connect_timeout] = 3
      opts[:read_timeout] = 3
      opts[:write_timeout] = 3
      mod_client = Docker::Connection.new("tcp://#{node.primary_ip}:2376", opts)
      Docker.ping(mod_client) != 'OK'
    rescue
      SystemEvent.where("message = ? AND created_at > ?", "#{node.label} Node Offline", 15.minutes.ago).delete_all
      SystemEvent.create!(
        message: "#{node.label} Node Offline",
        data: {
          'node' => {
            'id' => node.id,
            'name' => node.label,
            'primary_ip' => node.primary_ip
          }
        },
        event_code: '4490670b35a27164'
      )
      true
    end

  end
end
