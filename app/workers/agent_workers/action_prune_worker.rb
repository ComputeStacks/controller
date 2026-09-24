module AgentWorkers
  ##
  # Retention sweep for the changelog projection tables: terminal rows are kept for
  # audit/result-readback for a while, then pruned so the tables can't grow unbounded on a
  # busy fleet (mirrors the sibling event-table pruning in clock.rb). Covers:
  #   - container_action_requests (the pilot path), and
  #   - agent_tasks — task tombstones are intentionally ignored by the projector, so the
  #     table would otherwise grow forever and `AgentTask.needs_reconcile` re-scans it every
  #     15s. Only prune rows that are terminal AND fully reconciled (reconciled_status ==
  #     status) AND old, so an active/unreconciled transition is never dropped mid-flight.
  # Runs daily. `default` queue → worker_system.
  class ActionPruneWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    RETENTION = 7.days

    def perform
      ContainerActionRequest
        .where(status: ContainerActionRequests::StateManager::TERMINAL_STATUSES)
        .where("updated_at < ?", RETENTION.ago)
        .delete_all

      AgentTask
        .where(status: AgentTask::TERMINAL_STATUSES)
        .where("reconciled_status = status")
        .where("updated_at < ?", RETENTION.ago)
        .delete_all
    rescue => e
      ExceptionAlertService.new(e, "1694683a244a312d").perform
    end
  end
end
