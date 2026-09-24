module AgentWorkers
  ##
  # The reaction half of the projection model: reap stuck dispatches, coalesce
  # duplicate pending actions, apply the per-project dispatch budget, and enqueue
  # eligible rows. Runs unconditionally on a schedule (independent of new changelog entries)
  # so retries and reaping fire even when the changelog is quiet. No explicit queue
  # → `default` → worker_system.
  class ActionSweepWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    def perform
      ContainerActionServices::Sweep.new.call
    rescue => e
      ExceptionAlertService.new(e, "884eb7b1991d7b7e").perform
    end
  end
end
