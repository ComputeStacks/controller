module AgentWorkers
  ##
  # Every 2 minutes (lib/clock.rb), reads each node's maintenance status from its
  # agent, projects it, and repairs drift between the controller's request and the
  # controller hold the agent actually holds. The backstop for a lost push, a
  # missed changelog entry, or a node created already requesting maintenance.
  #
  # Fans out over EVERY node with an agent token -- disconnected or not, since
  # `disconnected` is a docker reachability flag that says nothing about the agent --
  # skipping only nodes whose agent answered 404 within the last hour.
  #
  # Per node, under the per-node maintenance lock shared with PushMaintenanceWorker:
  #   1. GET /v1/admin/maintenance (5 s). A failure is silent for the cycle; the
  #      alerts below and the status' observed_at surface a node that stays dark.
  #   2. Project the Status body and record `maintenance_status`.
  #   3. Reconcile: requested but the agent holds no current controller hold -> PUT;
  #      not requested but it still holds one -> DELETE. A pending override is handed
  #      to PushMaintenanceWorker#deliver with this pass' body: all=1 only for a node
  #      hold placed no later than the override; otherwise the override is retired
  #      (Nodes::MaintenanceProjection.override_decision).
  #   4. Alerts (deduped SystemEvents): a mismatch that survives a reconcile attempt
  #      into the next cycle; a hold older than 12 h; an agent < 3.4 on a node the
  #      controller wants in maintenance.
  class MaintenanceDriftWorker
    include Sidekiq::Worker

    sidekiq_options retry: false, queue: "default"

    GET_TIMEOUT = 5
    OLD_HOLD_AFTER = 12.hours
    UNSUPPORTED_ALERT_EVERY = 1.day

    # @param node_id [Integer, nil] nil fans out over every eligible node
    def perform(node_id = nil)
      if node_id.nil?
        Node.where.not(agent_token_encrypted: nil)
          .where("agent_maintenance_unsupported_at IS NULL OR agent_maintenance_unsupported_at < ?", 1.hour.ago)
          .pluck(:id).each { |id| self.class.perform_async(id) }
        return
      end

      node = Node.find_by(id: node_id)
      return if node.nil? || !node.agent_maintenance_supported?

      refresh!(node)
    rescue => e
      ExceptionAlertService.new(e, "a9214608b5a2bd07").perform
    end

    # GET the agent's maintenance status, project it, record `maintenance_status`,
    # and reconcile -- all under the per-node lock. Public: the admin "Refresh from
    # agent" action calls this directly (a live read, so it ignores the hourly
    # unsupported back-off; a 200 lifts it).
    #
    # @param node [Node]
    # @return [Symbol] :ok, :no_token, :locked (a push or drift pass holds the node),
    #   :unreachable (transport error / timeout), :unsupported (404, agent < 3.4),
    #   or :error (any other HTTP status)
    def refresh!(node)
      return :no_token if node.agent_token.blank?

      acquired, result = Nodes::MaintenanceProjection.with_lock(node) { refresh_locked(node) }
      acquired ? result : :locked
    end

    private

    def refresh_locked(node)
      node.reload
      status, body = begin
        Agent::Client.for_node(node).get_maintenance(timeout: GET_TIMEOUT)
      rescue Errno::ECONNREFUSED, SocketError, HTTP::Error => e
        Rails.logger.info("maintenance drift: #{node.label} unreachable (#{e.class})")
        return :unreachable
      end

      if status == 404
        Nodes::MaintenanceProjection.mark_unsupported!(node)
        alert_unsupported(node) if node.maintenance_requested
        return :unsupported
      end
      return :error unless status == 200 && body.is_a?(Hash)

      node.update_columns(agent_maintenance_unsupported_at: nil) if node.agent_maintenance_unsupported_at
      Nodes::MaintenanceProjection.apply_snapshot(node, body, seq: body["seq"])
      node.reload

      # Judge from the live body, not the projection: a PUT that only bumps the gen
      # (same reason) writes no changelog entry, so the projected controller.gen can
      # trail the agent's indefinitely. A successful reconcile's own response then
      # decides whether a mismatch remains.
      ctrl = body["controller"].is_a?(Hash) ? body["controller"] : nil
      local = body["local"].is_a?(Hash) ? body["local"] : nil
      after = ctrl
      if needs_push?(node, ctrl)
        begin
          pushed_status, pushed_body = AgentWorkers::PushMaintenanceWorker.new.deliver(node, observed: body)
          if pushed_status == 200 && pushed_body.is_a?(Hash)
            after = pushed_body["controller"].is_a?(Hash) ? pushed_body["controller"] : nil
          end
        rescue => e
          # The mismatch alert below reports it if it persists into the next cycle.
          Rails.logger.warn("maintenance drift: reconcile on #{node.label} failed: #{e.class}: #{e.message}")
        end
        node.reload
      end

      mismatch = node.maintenance_requested ? after.nil? : !after.nil?
      mismatch_since = track_mismatch(node, mismatch)
      node.update_columns(maintenance_status: {
        "running" => Array(body["running"]),
        "pending" => body["pending"],
        "quiesce" => body["quiesce"],
        "observed_at" => Time.current.iso8601,
        "mismatch_since" => mismatch_since
      })
      alert_old_holds(node, ctrl, local)
      :ok
    end

    # A pending override always goes to #deliver, which decides from this pass' body
    # whether it releases the node hold (all=1) or retires with nothing to do.
    def needs_push?(node, ctrl)
      if node.maintenance_requested
        ctrl.nil? || ctrl["gen"].to_i < node.maintenance_gen
      else
        !ctrl.nil? || Nodes::MaintenanceProjection.override_pending?(node)
      end
    end

    # A mismatch seen on two consecutive cycles -- i.e. one that a reconcile attempt
    # did not fix -- raises an alert. A single cycle is normal: the push may simply
    # not have landed yet.
    # @return [String, nil] the ISO8601 time the current mismatch was first seen
    def track_mismatch(node, mismatch)
      return nil unless mismatch

      since = (node.maintenance_status || {})["mismatch_since"]
      if since.present?
        alert_mismatch(node, since)
        since
      else
        Time.current.iso8601
      end
    end

    def alert_mismatch(node, since)
      held = node.maintenance_requested ? "requested here, but the agent holds no controller hold" : "released here, but the agent still holds a controller hold"
      msg = "Maintenance mismatch on #{node.label} [node #{node.id}]: #{held}"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, 1.hour.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn",
        data: {"node_id" => node.id, "since" => since, "gen" => node.maintenance_gen}, event_code: "35e33daf9aea22b2")
    end

    # Once per node per 12 h while any hold is older than 12 h.
    def alert_old_holds(node, ctrl, local)
      cutoff = OLD_HOLD_AFTER.ago.to_i
      old = {"controller" => ctrl, "node" => local}.select { |_, h| h && h["since"].to_i.positive? && h["since"].to_i < cutoff }
      return if old.empty?

      prefix = "Maintenance hold older than 12 hours on #{node.label} [node #{node.id}]"
      return if SystemEvent.where("event_code = ? AND message LIKE ? AND created_at > ?", "f6d9f90106e005b6", "#{prefix}%", OLD_HOLD_AFTER.ago).exists?

      detail = old.map do |holder, h|
        by = h["by"].present? ? " by #{h["by"]}" : ""
        "#{holder}#{by} since #{Time.at(h["since"].to_i).utc.iso8601} (#{h["reason"].presence || "no reason"})"
      end
      SystemEvent.create!(message: "#{prefix}: #{detail.join("; ")}", log_level: "warn",
        data: {"node_id" => node.id, "holds" => old}, event_code: "f6d9f90106e005b6")
    end

    def alert_unsupported(node)
      msg = "cs-agent on #{node.label} [node #{node.id}] is older than 3.4.0; maintenance is not enforced on the node"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, UNSUPPORTED_ALERT_EVERY.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn", data: {"node_id" => node.id}, event_code: "0ed589b8e20f1020")
    end
  end
end
