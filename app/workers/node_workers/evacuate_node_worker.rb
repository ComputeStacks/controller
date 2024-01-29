module NodeWorkers
  class EvacuateNodeWorker
    include Sidekiq::Worker
    sidekiq_options retry: false, queue: 'dep_critical'

    def perform(node_id, audit_id = nil)

      node = GlobalID::Locator.locate node_id
      return if node.nil?
      return unless node.region&.has_clustered_networking?

      audit = nil
      audit = GlobalID::Locator.locate(audit_id) if audit_id
      audit = Audit.create_from_object!(node, 'updated', '127.0.0.1') if audit.nil?

      event = EventLog.create!(
        locale: 'node.evacuating',
        locale_keys: { 'node' => node.label },
        event_code: '35bee537be0a0878',
        audit: audit,
        status: 'pending'
      )

      NodeServices::EvacuateNodeService.new(node, event).perform
    rescue => e
      ExceptionAlertService.new(e, '6ccf993cdd0cd74c').perform
    end

  end
end
