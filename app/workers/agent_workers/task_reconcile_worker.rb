module AgentWorkers
  ##
  # Drives controller EventLogs off projected agent_tasks (the changelog-driven
  # replacement for the retired csevent ingest). Runs unconditionally on a schedule so
  # transitions/heartbeats fire even when the changelog is quiet.
  #
  # Queue = `dep_critical` (worker_deployments): it mutates volume/backup EventLogs and
  # fires callbacks (deployment-domain work — the system queue would not run it in prod),
  # and it must stay live even when the lower pools are saturated — volume clones wait on
  # `dep_low` for the very transitions this worker produces.
  class TaskReconcileWorker
    include Sidekiq::Worker

    sidekiq_options queue: "dep_critical", retry: false

    def perform
      Agent::TaskReconciler.new.call
    rescue => e
      ExceptionAlertService.new(e, "6f2c8d1a0b7e4593").perform
    end
  end
end
