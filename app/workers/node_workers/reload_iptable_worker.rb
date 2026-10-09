module NodeWorkers
  class ReloadIptableWorker
    include Sidekiq::Worker
    sidekiq_options retry: false, queue: "dep_critical"

    def perform(node_id)
      node = GlobalID::Locator.locate node_id
      node.update_iptable_config!
    rescue Errno::ECONNREFUSED, Faraday::ConnectionFailed => e
      record_drop(node, e)
      SystemEvent.create!(
        message: "Reload Firewall Error",
        log_level: "warn",
        data: {
          "node_id" => node_id,
          "errors" => e.message
        },
        event_code: "cf3d664cb36f42ca"
      )
    rescue => e
      ExceptionAlertService.new(e, "da261f16697c3c66").perform
      record_drop(node, e)
      SystemEvent.create!(
        message: "Reload Firewall Error",
        log_level: "warn",
        data: {
          "node_id" => node_id,
          "errors" => e.message
        },
        event_code: "db1685e9133a738e"
      )
    end

    private

    # This worker is retry: false; the pending sync is what re-pushes the rules.
    def record_drop(node, error)
      return unless node.is_a?(Node)
      Agent::PendingSync.record!(region: node.region_id, node: node, kind: "firewall", error: error)
    end
  end
end
