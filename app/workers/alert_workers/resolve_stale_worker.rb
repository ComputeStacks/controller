module AlertWorkers
  ##
  # Resolves firing alerts that Alertmanager has stopped reporting.
  #
  # Alertmanager re-sends every firing alert each repeat_interval (1h) and sends a
  # resolve only once. If that resolve is lost or misapplied, the alert would show as
  # firing forever; one unreported for STALE_AFTER is treated as resolved.
  #
  # Alertmanager also stops sending an alert while it is silenced or inhibited, and
  # nothing arrives while the controller is unreachable. Those get resolved too, and
  # notify again as a new firing if they are still firing afterwards.
  #
  # The migration that added last_reported_at set it for every alert already firing;
  # updated_at is only a backstop for a firing alert somehow left without one.
  class ResolveStaleWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    STALE_AFTER = 6.hours

    def perform
      AlertNotification.active
        .where("COALESCE(last_reported_at, updated_at) < ?", STALE_AFTER.ago)
        .find_each { |alert| alert.update(status: "resolved") }
    end
  end
end
