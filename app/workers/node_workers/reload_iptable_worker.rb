module NodeWorkers
  class ReloadIptableWorker
    include Sidekiq::Worker
    sidekiq_options retry: false, queue: 'dep_critical'

    def perform(node_id)
      node = GlobalID::Locator.locate node_id
      node.update_iptable_config!
    rescue Errno::ECONNREFUSED, Faraday::ConnectionFailed => e
      SystemEvent.create!(
        message: "Reload Firewall Error",
        log_level: 'warn',
        data: {
          'node_id' => node_id,
          'errors' => e.message
        },
        event_code: 'cf3d664cb36f42ca'
      )
    rescue => e
      ExceptionAlertService.new(e, 'da261f16697c3c66').perform
      SystemEvent.create!(
        message: "Reload Firewall Error",
        log_level: 'warn',
        data: {
          'node_id' => node_id,
          'errors' => e.message
        },
        event_code: 'db1685e9133a738e'
      )
    end

  end
end
