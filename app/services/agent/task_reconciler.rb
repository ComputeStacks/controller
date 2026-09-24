module Agent
  ##
  # Drives controller EventLogs off the projected cs-agent `task` snapshots
  # (agent_tasks) — the changelog-driven replacement for the retired csevent ingest
  # (`POST /api/system/events`). For each task it resolves-or-**creates** the correlated
  # EventLog (mirroring the create/auto-Audit path of the old Api::System::EventsController
  # #create) and drives it pending→running→terminal so the backup/restore/export/delete
  # UX, callbacks, and `operation_in_progress?` gating keep working with no live stream.
  #
  # **Correlation is by a `task_id` label stamped on the EventLog**, not by audit_id:
  # agent-originated tasks (scheduled backups) carry no audit, and even for tasks that do,
  # the projector's snapshot-upsert would clobber a persisted audit_id back to the agent's
  # value on the next poll. The label lives on the EventLog (which the projector never
  # touches), so it is stable across every transition — one event per task, found again
  # each pass. A pre-created controller event (no label yet) is matched once via
  # audit_id + event_code and then stamped.
  #
  # Two responsibilities per pass (AgentWorkers::TaskReconcileWorker, dep_critical, 15s):
  #   1. TRANSITION reaction — for tasks whose latest projected status hasn't been reacted
  #      to (`needs_reconcile`), take a row lock and, in one transaction, drive the EventLog
  #      and advance `reconciled_status`. The row lock serializes overlapping passes (no
  #      duplicate events / double callbacks); the transaction means a crash rolls the whole
  #      transition back so it retries (at-least-once) rather than being silently consumed.
  #   2. HEARTBEAT — touch the correlated event of every still-active, still-fresh task so
  #      EventWorkers::StaleEventWorker (fails `running` events older than 1h) doesn't
  #      spuriously fail a long backup/restore/clone. Bounded by task freshness so a dead
  #      node (frozen projection) can't heartbeat a zombie event forever and permanently
  #      wedge `operation_in_progress?`.
  class TaskReconciler
    MAX_TEARDOWN_REISSUES = 3

    # task.name -> EventLog locale (the four backup-family flows; matches the retired
    # csevent locales — see handoff §7 / the api/volumes/*_controller pre-created events).
    LOCALE = {
      "volume.backup" => "volume.backup",
      "volume.restore" => "volume.restore",
      "backup.delete" => "backup.delete",
      "backup.export" => "volume.download"
    }.freeze

    def call
      AgentTask.needs_reconcile.find_each { |task| react(task) }
      heartbeat_active
      reissue_failed_teardowns
    end

    private

    # The agent does not auto-retry a failed volume.trash (handoff §4) — re-issue the DELETE
    # (which resets the teardown failed->pending, EnqueueTeardown resetFailed=true) up to a
    # cap. Runs OUTSIDE react's per-task row lock (this makes an HTTP call). A CAS bump on
    # reissue_count means only one pass re-issues per increment; at the cap we stop (the
    # failed transition already surfaced a SystemEvent via handle_teardown).
    def reissue_failed_teardowns
      AgentTask.where(name: "volume.trash", status: "failed")
        .where("reissue_count < ?", MAX_TEARDOWN_REISSUES).find_each do |task|
        claimed = AgentTask.where(id: task.id, reissue_count: task.reissue_count)
          .update_all(reissue_count: task.reissue_count + 1) == 1
        next unless claimed
        node = task.node_id && Node.find_by(id: task.node_id)
        next if node.nil?
        Agent::Client.for_node(node).delete_volume(task.project_id.to_s, task.volume)
      rescue => e
        ExceptionAlertService.new(e, "e4a9c2f70b8d1536").perform
      end
    end

    # Drive one transition atomically under a row lock: overlapping passes serialize on
    # the lock (so only one creates/drives the event), and driving + advancing the
    # watermark commit together (a crash rolls both back and the transition retries).
    def react(task)
      task.with_lock do
        target = task.status
        next if task.reconciled_status == target # already handled (re-checked under lock)
        drive(task, target)
        task.update_column(:reconciled_status, target) # NB update_column: does not bump updated_at (the freshness signal)
      end
    rescue => e
      ExceptionAlertService.new(e, "d3b6a1c58e0f4297").perform
    end

    def drive(task, target)
      return handle_teardown(task, target) if task.name == "volume.trash"

      event = correlated_event(task) || create_event(task)
      return if event.nil?

      case target
      when "running"
        event.start! if event.pending?
      when "completed"
        # This ordering is INERT — it fixes nothing and changes no atomicity. Both statements
        # run inside react's `task.with_lock` transaction (event.done!'s `update` joins it
        # rather than opening a savepoint), so either order commits both rows together or
        # neither: under the old order a `create!` failure already rolled the transition
        # back, and under this order `done!` simply never runs. The callback payload is
        # likewise unaffected, since the enqueue is deferred past COMMIT
        # (Events::StateManager#perform_callback_reply!). EventLogDatum has no callbacks and
        # no `touch:`. It is kept ahead of the transition purely so the result summary is in
        # place before anything can observe a completed event.
        record_result_detail(event, task) if event.active? # surface the structured result on the event
        event.done!
      when "failed"
        event.fail!(failure_reason(task))
      when "cancelled"
        event.cancel!(failure_reason(task))
      end
      # "pending" → the event exists (pending); nothing to drive yet.
    end

    # Touch the correlated event of every active task WHOSE NODE IS ONLINE so
    # StaleEventWorker can't fail a legitimately long backup/restore/clone. Node liveness
    # (not task `updated_at`) is the right bound: the agent only emits a task changelog row
    # on a status transition, so `updated_at` goes stale mid-backup — but as long as the
    # node is up the agent WILL report the terminal state, so the event should stay alive.
    # When the node goes offline the touch stops and StaleEventWorker reaps the event,
    # clearing operation_in_progress? (no permanent zombie wedge).
    def heartbeat_active
      AgentTask.active.includes(:node).find_each do |task|
        next unless task.node&.online?
        event = correlated_event(task)
        event.touch if event&.running?
      end
    end

    # @return [EventLog, nil] the event for this task — by task_id label (stable), else the
    #   pre-created controller event (audit_id + event_code), which we then stamp with the
    #   label so subsequent passes match on it.
    def correlated_event(task)
      code = task.event_code
      return nil if code.blank?

      labelled = EventLog.where("labels ->> 'task_id' = ?", task.id).order(created_at: :desc).first
      return labelled if labelled

      audit = lookup_audit(task)
      return nil if audit.nil?
      # Only adopt a pre-created event that isn't already claimed by a different task
      # (two ops sharing audit_id+event_code must not ping-pong one event).
      event = audit.event_logs.where(event_code: code)
        .where("labels ->> 'task_id' IS NULL OR labels ->> 'task_id' = ?", task.id)
        .order(created_at: :desc).first
      stamp_task_id(event, task) if event
      event
    end

    # Create the EventLog for a task that has none — an agent-originated backup
    # (scheduler) or a clone-internal backup/restore where the controller never
    # pre-created one. Mirrors Api::System::EventsController#create (incl. auto-Audit
    # when the task carries no audit). Stamped with the task_id label for later matching.
    # @return [EventLog, nil]
    def create_event(task)
      locale = LOCALE[task.name]
      return nil if locale.blank?
      volume = Volume.find_by(name: task.volume)
      return nil if volume.nil?

      audit = lookup_audit(task) || Audit.create(event: "updated", rel_id: volume.id, rel_model: "Volume")
      return nil if audit.nil? || audit.new_record?

      event = EventLog.new(locale: locale, locale_keys: {}, status: "pending",
        audit: audit, event_code: task.event_code, labels: {"task_id" => task.id})
      event.volumes << volume
      event.deployments << volume.deployment if volume.deployment
      event.container_services << volume.container_service if volume.container_service
      return event if event.save

      # Persistent save failure would silently skip the transition — surface it.
      Rails.logger.warn("TaskReconciler could not create event for task #{task.id}: #{event.errors.full_messages.join("; ")}")
      SystemEvent.create!(message: "TaskReconciler failed to create EventLog for task #{task.id}",
        log_level: "warn", data: {"task_id" => task.id, "errors" => event.errors.full_messages},
        event_code: "c5a90e37b21d4f68")
      nil
    end

    def stamp_task_id(event, task)
      return if event.labels["task_id"] == task.id
      event.update(labels: event.labels.merge("task_id" => task.id))
    end

    def lookup_audit(task)
      return nil if task.audit_id.blank? || task.audit_id.to_i.zero?
      Audit.find_by(id: task.audit_id)
    end

    def failure_reason(task)
      r = task.result.is_a?(Hash) ? task.result : {}
      r["output"].presence || r["error"].presence || "Task #{task.status}"
    end

    # On success the agent carries only structured fields in `result` (no per-step borg
    # output — that stays in the agent logs). Surface what we do have as one event_detail
    # line so a completed backup/export isn't blank on the event. Deliberately omits the
    # presigned url/object_key (the export UI owns that) and, of course, failure output.
    def record_result_detail(event, task)
      summary = result_summary(task.result)
      return if summary.blank?
      event.event_details.create!(data: summary, event_code: "d9b4f1a7c2e05386")
    end

    def result_summary(result)
      return nil unless result.is_a?(Hash)
      parts = []
      parts << "Last backup: #{format_result_time(result["last_backup"])}" if result["last_backup"].present?
      parts << "Size: #{result["size"]} bytes" if result["size"].present?
      parts << "Expires: #{format_result_time(result["expiry"])}" if result["expiry"].present?
      parts.presence&.join(" · ")
    end

    def format_result_time(value)
      Time.at(value.to_i).utc.strftime("%Y-%m-%d %H:%M:%S UTC")
    rescue
      value.to_s
    end

    # A failed teardown is NOT auto-retried by the agent — surface it. (The bounded
    # re-issue of the DELETE is wired in alongside Agent::Client#delete_volume.)
    def handle_teardown(task, target)
      return unless target == "failed"
      msg = "cs-agent volume.trash failed for volume #{task.volume} (task #{task.id})"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, 1.hour.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn",
        data: {"task_id" => task.id, "volume" => task.volume, "result" => task.result},
        event_code: "b7e1f0a4c9d23685")
    end
  end
end
