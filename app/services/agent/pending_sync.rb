module Agent
  ##
  # Dirty marks for agent writes that were dropped (`agent_pending_syncs`).
  #
  # Every kind is a full-state, idempotent PUT or DELETE that can be recomputed from the
  # DB, so a row records only "(region, subject, kind, key) is out of sync" and
  # AgentWorkers::PendingSyncWorker recomputes the body from CURRENT data on replay.
  #
  # Live writers follow one pattern:
  #
  #   gen = Agent::PendingSync.generation_for(...)   # BEFORE computing the body
  #   ok  = <push>
  #   ok ? Agent::PendingSync.clear!(..., if_generation: gen) : Agent::PendingSync.record!(...)
  #
  # `generation` is bumped by every record!, and clear!/replay only delete the row at the
  # generation they read, so a drop recorded by a concurrent writer survives a stale
  # writer's success.
  module PendingSync
    PROJECT_KINDS = %w[tenant tenant_delete managed_metadata managed_ssh_keys managed_sftp_host_keys].freeze
    KINDS = (%w[firewall] + PROJECT_KINDS).freeze

    # Replay order within a region.
    ORDER = %w[firewall tenant_delete tenant managed_metadata managed_ssh_keys managed_sftp_host_keys].freeze

    module_function

    # Record (upsert) a dropped write. Never raises into the caller: losing a dirty mark is
    # no worse than the drop it describes.
    #
    # - keeps first_failed_at, bumps generation, sets last_error and next_attempt_at = now,
    #   and clears dead_at (a revived dead row also starts its attempt count afresh);
    # - `tenant_delete` supersedes every other row for that (region, project);
    # - a no-op for the other project kinds while the project is being deleted.
    #
    # @param region [Region, Integer]
    # @param project [Deployment, Integer, nil]
    # @param node [Node, Integer, nil]
    # @param kind [String]
    # @param key [String] the sftp container name for managed_sftp_host_keys
    # @param error [String, Exception, nil]
    # @return [Boolean] whether a row was recorded
    def record!(region:, kind:, project: nil, node: nil, key: "", error: nil)
      kind = kind.to_s
      raise ArgumentError, "unknown pending sync kind #{kind}" unless KINDS.include?(kind)
      region_id = id_of(region)
      project_id = id_of(project)
      node_id = id_of(node)
      return false if region_id.nil?
      if kind != "tenant_delete" && kind != "firewall" && TenantRegistry.deleting?(project_id)
        return false
      end

      now = Time.current
      error = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
      ActiveRecord::Base.transaction(requires_new: true) do
        if kind == "tenant_delete"
          AgentPendingSync.where(region_id: region_id, project_id: project_id).where.not(kind: "tenant_delete").delete_all
        end
        sql = <<~SQL.squish
          INSERT INTO agent_pending_syncs
            (region_id, project_id, node_id, kind, key, generation, attempts, last_error,
             first_failed_at, next_attempt_at, created_at, updated_at)
          VALUES (:region_id, :project_id, :node_id, :kind, :key, 1, 0, :error, :now, :now, :now, :now)
          ON CONFLICT (region_id, COALESCE(project_id, 0), COALESCE(node_id, 0), kind, key)
          DO UPDATE SET
            generation = agent_pending_syncs.generation + 1,
            last_error = EXCLUDED.last_error,
            next_attempt_at = EXCLUDED.next_attempt_at,
            attempts = CASE WHEN agent_pending_syncs.dead_at IS NULL THEN agent_pending_syncs.attempts ELSE 0 END,
            first_attempted_at = CASE WHEN agent_pending_syncs.dead_at IS NULL THEN agent_pending_syncs.first_attempted_at ELSE NULL END,
            dead_at = NULL,
            updated_at = EXCLUDED.updated_at
        SQL
        ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql,
          {region_id:, project_id:, node_id:, kind:, key: key.to_s, error:, now:}]))
      end
      true
    rescue ArgumentError
      raise
    rescue => e
      ExceptionAlertService.new(e, "c58d0b1e6a2f7394").perform
      false
    end

    # The live-writer pattern in one place. Reads the generation, runs the push (which must
    # compute its body INSIDE the block, after the read), then clears on success or records
    # on failure. A NotReady raised by the push is recorded and re-raised.
    # With record_drop: false (replay) it just runs the push.
    # @yieldreturn [Boolean] whether the agent accepted the write
    # @return [Boolean]
    def track(record_drop:, region:, kind:, project: nil, node: nil, key: "")
      return yield unless record_drop
      subject = {region:, kind:, project:, node:, key:}
      gen = generation_for(**subject)
      ok = yield
      if ok
        clear!(**subject, if_generation: gen)
      else
        record!(**subject, error: "agent did not accept the #{kind} push")
      end
      ok
    rescue Agent::Client::NotReady => e
      record!(**subject, error: e) if record_drop
      raise
    end

    # The row's generation, read BEFORE the caller computes its body. nil = no row.
    # @return [Integer, nil]
    def generation_for(region:, kind:, project: nil, node: nil, key: "")
      scope_for(region:, kind:, project:, node:, key:).pick(:generation)
    end

    # After a successful live push: delete the row only at the generation read before the
    # body was computed. With no row at read time (nil), there is nothing to clear.
    # @return [Boolean] whether a row was deleted
    def clear!(region:, kind:, if_generation:, project: nil, node: nil, key: "")
      return false if if_generation.nil?
      scope_for(region:, kind:, project:, node:, key:).where(generation: if_generation).delete_all.positive?
    end

    def scope_for(region:, kind:, project: nil, node: nil, key: "")
      AgentPendingSync.where(
        region_id: id_of(region),
        project_id: id_of(project),
        node_id: id_of(node),
        kind: kind.to_s,
        key: key.to_s
      )
    end

    def id_of(obj)
      case obj
      when nil then nil
      when Integer then obj
      when ActiveRecord::Base then obj.id
      else Integer(obj.to_s, exception: false)
      end
    end
  end
end
