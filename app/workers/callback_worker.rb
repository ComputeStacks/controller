class CallbackWorker
  include Sidekiq::Worker

  def perform(args = {})
    return if args["callback"].empty?

    event = if args["event_id"]
      EventLog.find_by(id: args["event_id"])
    end

    data = args["data"]
    timestamp = args["timestamp"]

    # This reads the event's state at JOB-EXECUTION time, on this worker's own connection,
    # seconds to minutes after the push — and nothing keeps the event terminal in between.
    # So an active event here has two plausible causes, and both mean "the outcome we would
    # report is not the real one":
    #
    #   1. The push escaped its transaction (the bug this guard backstops): the terminal
    #      transitions were pushed from inside an open transaction, and we are reading
    #      pre-commit state. CallbackService would derive `success: false` from it and the
    #      receiver would record that permanently.
    #   2. The event was legitimately RE-ACTIVATED after its terminal transition.
    #      Events::StateManager#start! (state_manager.rb:54) guards only `failed? ||
    #      cancelled?`, so a `completed` event can be flipped back to `running`. The power
    #      workers that begin `return unless event.start!`
    #      (ContainerWorkers::{Start,Stop,Restart,Rebuild}Worker, `retry: 1`) do exactly that
    #      when re-run against an event Containers::PowerManager#power_cycle_response
    #      already drove to `completed` — e.g. a SIGTERM-requeued job during a deploy. Those
    #      events do carry a callback_url (power_cycle_container_service.rb:164-166).
    #
    # Either way, defer: wait for a terminal state rather than reporting a wrong one.
    if event&.active?
      # Re-check the cutoff INSIDE the guard: without it, an event that stays active
      # forever (e.g. a rolled-back transition) would re-enqueue itself indefinitely.
      if Time.at(timestamp) <= 4.hours.ago.to_time
        return log_callback_abandoned(event, timestamp)
      end
      log_active_event_anomaly event
      return CallbackWorker.perform_in 30.seconds, args
    end

    cb = CallbackService.new timestamp
    cb.authorization_header = args["callback"]["authorization"]
    cb.url = args["callback"]["url"]
    cb.event_log = event if event
    cb.data = data if event.nil?
    return if cb.perform

    # If we've been trying for more than 4 hours, stop.
    return if Time.at(timestamp) <= 4.hours.ago.to_time

    CallbackWorker.perform_in next_retry(timestamp), args
  end

  private

  # Transient and self-healing: the retry will pick up the real state. Recorded anyway so a
  # returning ordering bug (cause 1 above) isn't silently masked by the retry. Deduped per
  # event per hour, so the *matched* message deliberately carries no status — a stuck event
  # moving pending -> running must not produce a second row inside the same hour. The status
  # lives in `data` instead.
  def log_active_event_anomaly(event)
    msg = "CallbackWorker deferred: event #{event.id} is not in a terminal state yet"
    # Lead with event_code (indexed); `message` is not, and this guard can run ~480 times
    # per stuck event over the 4-hour budget. (`data` can't be matched on — it is a
    # YAML-serialized text column, not jsonb.)
    return if SystemEvent.where(event_code: "4b5ba53233315e32")
      .where("message = ? AND created_at > ?", msg, 1.hour.ago).exists?
    SystemEvent.create!(message: msg, log_level: "warn",
      data: {"event_id" => event.id, "status" => event.status},
      event_code: "4b5ba53233315e32", audit_id: event.audit_id)
  end

  # Terminal, and the reason this needs a durable record rather than only a log line inside
  # a Sidekiq container: the 4-hour budget is exhausted, so this callback will NEVER be
  # delivered and whatever is waiting on it (backup/restore/export) never hears back. Fires
  # at most once per callback, so no dedup is needed.
  def log_callback_abandoned(event, timestamp)
    msg = "CallbackWorker giving up on event #{event.id}: still #{event.status} after the 4-hour retry budget; no callback will be delivered"
    Rails.logger.warn(msg)
    SystemEvent.create!(message: msg, log_level: "warn",
      data: {"event_id" => event.id, "status" => event.status, "timestamp" => timestamp},
      event_code: "9d7928ffd15b3a3a", audit_id: event.audit_id)
    nil
  end

  def next_retry(timestamp)
    ts = Time.at timestamp
    # Within 5 minutes, try again in 2 minutes
    return 5.minutes if ts >= 2.minutes.ago.to_time

    # Within 10 minutes, try again in 5
    return 10.minutes if ts >= 5.minutes.ago.to_time

    # default is every 15
    15.minutes
  end
end
