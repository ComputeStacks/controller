module Agent
  ##
  # Projects one node's cs-agent changelog into local typed projection tables — the
  # controller's rebuildable view of node-reported truth (pull-only up-channel). The
  # single per-node `Node#changelog_cursor` is the high-water mark of consumed `seq`;
  # `Node#changelog_acked` is the durable watermark reported back to the agent (drives
  # its prune). Both advance monotonically; ack is reported strictly after projection.
  #
  # v3.0.0 entity set = { task, volume, firewall_rule, repository, action_request }.
  #   - `action_request` → container_action_requests (first-seen-wins; the pilot path).
  #   - `task`           → agent_tasks (snapshot-upsert by id; reacted by TaskReconciler).
  #   - `repository`     → agent_repositories (snapshot-upsert by name; backs repo_info).
  #   - `volume`/`firewall_rule` → NO-OP: pure echoes of our own DOWN PUTs (we own that
  #     state; reacting would be a no-op). Projected nowhere on purpose.
  #
  # Projection is a blind, idempotent upsert; we act on state transitions in the
  # projection (TaskReconciler / ContainerActionServices::Sweep), never off re-reading
  # the log, so a snapshot re-emitting at a higher seq never re-fires.
  #
  # **Single projector per node.** The snapshot-upserts are only monotonic if one pass
  # runs per node at a time (the 15s fan-out could otherwise overlap on a slow node and a
  # stale pass could downgrade a task or regress the cursor). A per-node Postgres advisory
  # try-lock serializes them — a would-be overlapping pass simply skips. Cursor/ack are
  # written with GREATEST so they can never regress even if an in-memory value is stale.
  #
  # **Unknown-type / unprojectable guard:** the cursor (and therefore the ack) advances
  # only to the max seq *strictly below* the first row we cannot fully project (an
  # unrecognized entity_type, or a malformed task/repository). This halts the channel
  # (loudly, via SystemEvent) rather than acking past — and thus letting the agent prune
  # — a row we didn't durably store. Co-release keeps this from happening in normal ops.
  class ChangelogProjector
    PULL_LIMIT = 1000
    MAX_PARAMS_BYTES = 16_384
    KNOWN_TYPES = %w[task volume firewall_rule repository action_request].freeze
    ADVISORY_LOCK_CLASS = 0x63730001 # arbitrary constant namespace for the per-node lock

    # @param node [Node]
    def initialize(node)
      @node = node
    end

    def call
      return unless try_lock # another projector holds this node; skip (no overlap)
      begin
        project
      ensure
        unlock
      end
    end

    private

    def project
      entries = Agent::Client.for_node(@node).changelog(since: @node.changelog_cursor, limit: PULL_LIMIT)
      return flush_ack if entries.empty? # steady state; still flush a pending ack

      sorted = entries.sort_by { |e| e["seq"].to_i }

      # Halt strictly below the first row we can't fully project (never skip-and-ack a
      # task/repository we didn't store, or an unknown type).
      halt_idx = sorted.index { |e| !projectable?(e) }
      projectable = halt_idx ? sorted[0...halt_idx] : sorted

      project_action_requests(projectable.select { |e| e["entity_type"] == "action_request" })
      project_tasks(projectable.select { |e| e["entity_type"] == "task" })
      project_repositories(projectable.select { |e| e["entity_type"] == "repository" })
      # volume / firewall_rule: intentional no-op (echoes).

      safe_seq =
        if halt_idx
          projectable.map { |e| e["seq"].to_i }.max || @node.changelog_cursor
        else
          sorted.map { |e| e["seq"].to_i }.max
        end

      advance_cursor(safe_seq)
      flush_ack
      report_unprojectable(sorted[halt_idx]) if halt_idx # alert last; never blocks the safe-prefix advance
    end

    # A row is unprojectable (→ halt the cursor below it) when its entity_type is
    # unknown, or a reacted-type upsert lacks a field we need to react on later.
    # action_request malformed rows are terminal-at-projection (safe to skip-and-advance,
    # as the pilot did), so they are NOT a halt.
    def projectable?(entry)
      type = entry["entity_type"]
      return false unless KNOWN_TYPES.include?(type)
      return true if entry["op"] == "delete" # tombstone (no payload) — handled per type

      case type
      when "task"
        # name is required to map the EventLog event_code the reconciler correlates on.
        task_id(entry).present? && entry.dig("payload", "status").present? && entry.dig("payload", "name").present?
      when "repository"
        repo_name(entry).present?
      else
        true
      end
    end

    # --- action_request (unchanged pilot semantics: first-seen-wins) --------------

    def project_action_requests(entries)
      rows = entries.filter_map { |e| action_request_row(e) }
      ContainerActionRequest.insert_all(rows, unique_by: :action_id) if rows.any?
    end

    # @return [Hash, nil] attributes for insert_all, or nil to skip.
    def action_request_row(entry)
      return nil if entry["op"] == "delete" # tombstone — nothing to project/act on

      payload = entry["payload"] || {}
      action_id = entry["entity_id"].presence || payload["id"].presence
      return nil if action_id.blank?

      action_type = payload["action_type"].to_s
      return nil if action_type.blank?

      params = payload["params"] || {}
      now = Time.current

      status, reason, stored_params =
        if params.to_json.bytesize > MAX_PARAMS_BYTES
          ["rejected", "params exceed #{MAX_PARAMS_BYTES} bytes", {}]
        elsif ContainerActionRegistry.handles?(action_type)
          ["received", nil, params]
        else
          ["unhandled", "no handler registered for #{action_type}", params]
        end

      {
        action_id: action_id,
        node_id: @node.id,
        project_id: (entry["project_id"].presence || payload["project_id"]).to_s,
        action_type: action_type,
        params: stored_params,
        status: status,
        state_reason: reason,
        changelog_seq: entry["seq"].to_i,
        created_at: now,
        updated_at: now
      }
    end

    # --- task (snapshot-upsert by id) ----------------------------------------------

    def project_tasks(entries)
      # Task deletes are ignored (the controller keeps its own task history).
      upserts = entries.reject { |e| e["op"] == "delete" }
      return if upserts.empty?

      # Highest-seq snapshot per id (a batch holds pending→running→completed; upsert_all
      # rejects two conflicting rows for one key in a single statement). Serialized +
      # cursor-ordered delivery means the surviving snapshot is always the newest, so the
      # blind upsert is monotonic — and a reused id (e.g. volume.trash:<name> reset from
      # failed→pending at a higher seq) correctly overwrites (no "terminal is forever" trap).
      rows = highest_seq_per(upserts) { |e| task_id(e) }.values.map { |e| task_row(e) }
      AgentTask.upsert_all(
        rows,
        unique_by: :id,
        update_only: %i[name status result audit_id volume node_id project_id changelog_seq]
      )
    end

    def task_row(entry)
      p = entry["payload"] || {}
      now = Time.current
      {
        id: task_id(entry),
        name: p["name"].to_s,
        status: p["status"].to_s,
        result: p["result"],
        audit_id: p["audit_id"],
        volume: p["volume"],
        node_id: @node.id,
        # Keep an absent project_id as nil (not ""); the agent renders "0" for detached
        # volumes, so "" would be a spurious third value PR3's sentinel queries would miss.
        project_id: entry["project_id"].presence || p["project_id"].presence,
        changelog_seq: entry["seq"].to_i,
        created_at: now,
        updated_at: now
      }
    end

    # --- repository (snapshot-upsert by name; delete tombstone removes the row) -----

    def project_repositories(entries)
      latest = highest_seq_per(entries) { |e| repo_name(e) }
      return if latest.empty?

      deletes, upserts = latest.values.partition { |e| e["op"] == "delete" }
      del_names = deletes.map { |e| repo_name(e) }
      AgentRepository.where(name: del_names).delete_all if del_names.any?

      rows = upserts.map { |e| repo_row(e) }
      return if rows.empty?

      AgentRepository.upsert_all(
        rows,
        unique_by: :name,
        update_only: %i[size_on_disk total_size archives node_id changelog_seq agent_updated_at]
      )
    end

    def repo_row(entry)
      p = entry["payload"] || {}
      now = Time.current
      {
        name: repo_name(entry),
        size_on_disk: p["size_on_disk"],
        total_size: p["total_size"],
        archives: p["archives"] || [],
        node_id: @node.id,
        changelog_seq: entry["seq"].to_i,
        agent_updated_at: coerce_time(p["updated_at"]),
        created_at: now,
        updated_at: now
      }
    end

    # --- cursor + ack --------------------------------------------------------------

    # Advance with GREATEST so a stale in-memory value can never regress the DB.
    def advance_cursor(seq)
      Node.where(id: @node.id).update_all(["changelog_cursor = GREATEST(changelog_cursor, ?)", seq.to_i])
      @node.changelog_cursor = [@node.changelog_cursor, seq].max
    end

    # Report the durable projection watermark to the agent (drives its prune). Only POST
    # when the cursor has moved past the last acked seq; monotonic, tolerant. GREATEST on
    # the write guards against regression.
    def flush_ack
      seq = @node.changelog_cursor
      return if seq <= @node.changelog_acked
      return unless Agent::Client.for_node(@node).ack_changelog(seq)
      Node.where(id: @node.id).update_all(["changelog_acked = GREATEST(changelog_acked, ?)", seq.to_i])
      @node.changelog_acked = [@node.changelog_acked, seq].max
    end

    # --- per-node advisory lock ----------------------------------------------------

    def try_lock
      ActiveRecord::Base.connection.select_value(
        "SELECT pg_try_advisory_lock(#{ADVISORY_LOCK_CLASS}, #{@node.id.to_i})"
      )
    end

    def unlock
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_unlock(#{ADVISORY_LOCK_CLASS}, #{@node.id.to_i})"
      )
    end

    # --- helpers -------------------------------------------------------------------

    # Reduce entries to the highest-seq entry per key (keyed by the block).
    def highest_seq_per(entries)
      entries.each_with_object({}) do |e, acc|
        key = yield(e)
        next if key.blank?
        acc[key] = e if acc[key].nil? || e["seq"].to_i > acc[key]["seq"].to_i
      end
    end

    def task_id(entry)
      entry["entity_id"].presence || entry.dig("payload", "id").presence
    end

    def repo_name(entry)
      entry["entity_id"].presence || entry.dig("payload", "name").presence
    end

    def coerce_time(value)
      return nil if value.blank?
      return Time.at(value).utc if value.is_a?(Numeric)
      return Time.at(value.to_i).utc if value.is_a?(String) && value.match?(/\A\d+\z/)
      value
    rescue
      nil
    end

    # An unrecognized entity_type (or malformed reacted-type row) stalls the channel at
    # this node. Surface it, deduped to once per 15 min per node — a wedged node must be
    # observable without alert spam. (Mirrors Agent::Client#report_changelog_error.)
    def report_unprojectable(entry)
      detail = "entity_type=#{entry["entity_type"].inspect} seq=#{entry["seq"]}"
      Rails.logger.warn("agent changelog unprojectable node=#{@node.id} #{detail}")
      msg = "cs-agent changelog unprojectable row on #{@node.label} (#{detail})"
      return if SystemEvent.where("message = ? AND created_at > ?", msg, 15.minutes.ago).exists?
      SystemEvent.create!(message: msg, log_level: "warn",
        data: {"node_id" => @node.id, "detail" => detail}, event_code: "a1f4c7e29b6d0358")
    end
  end
end
