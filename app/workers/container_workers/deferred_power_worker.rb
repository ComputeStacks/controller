module ContainerWorkers
  ##
  # Runs the power actions PowerCycleContainerService parked while a node was in
  # maintenance: pending EventLogs labeled with the node's id. Kicked when the node's
  # maintenance ends (Nodes::MaintenanceTransitions) and when it comes back online.
  #
  # Nothing runs until the node is online: released while still disconnected (mid-reboot),
  # the events stay parked for the reconnect kick. Each event is unlabeled before it is
  # re-run, so a kick that arrives twice never runs it twice, and relabeled if the re-run
  # raises. If the node is in maintenance again, the service simply parks it again.
  class DeferredPowerWorker
    include Sidekiq::Worker

    sidekiq_options retry: 1

    # @param [Integer] node_id
    def perform(node_id)
      node = Node.find_by(id: node_id)
      return if node.nil? || !node.online?

      EventLog.where(status: "pending")
        .where("labels ->> ? = ?", PowerCycleContainerService::DEFERRED_NODE_LABEL, node.id.to_s)
        .order(:id).each { |event| resume!(event) }
    end

    private

    def resume!(event)
      parked_labels = event.labels
      labels = event.labels.dup
      action = labels.delete(PowerCycleContainerService::DEFERRED_ACTION_LABEL)
      labels.delete(PowerCycleContainerService::DEFERRED_NODE_LABEL)
      container_gid = labels.delete(PowerCycleContainerService::DEFERRED_CONTAINER_LABEL)
      claimed = EventLog.where(id: event.id, status: "pending")
        .where("labels ->> ? IS NOT NULL", PowerCycleContainerService::DEFERRED_NODE_LABEL)
        .update_all(labels: labels, updated_at: Time.current)
      return if claimed.zero?
      event.reload

      container = begin
        GlobalID::Locator.locate(container_gid)
      rescue ActiveRecord::RecordNotFound
        nil
      end
      if container.nil?
        event.cancel! "Container no longer exists"
        return
      end

      service = PowerCycleContainerService.new(container, action, event.audit)
      service.event = event
      service.perform
    rescue => e
      ExceptionAlertService.new(e, "8e2a64f1c07d3b95").perform
      # Park it again for the next kick rather than leave it pending and unlabeled.
      EventLog.where(id: event.id, status: "pending").update_all(labels: parked_labels) if parked_labels
    end
  end
end
