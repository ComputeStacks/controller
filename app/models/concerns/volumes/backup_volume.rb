module Volumes
  module BackupVolume
    extend ActiveSupport::Concern

    # Why the last backup-family call returned false without reaching a node, or nil.
    # Controllers use it as the event's failure reason instead of a bare "Fatal Error".
    attr_reader :dispatch_error

    # The machine-readable reason alongside #dispatch_error: "node_maintenance" or
    # "node_offline" (also used when the volume has no node), or nil. The API answers 409
    # with it.
    attr_reader :dispatch_error_code

    # Why a backup-family task can't be dispatched right now, or nil. A node in maintenance
    # pauses task claiming, so refuse up front rather than queue a task that runs hours later.
    def task_dispatch_blocker
      task_dispatch_block&.first
    end

    # @return [Array(String, String), nil] the message and its code, or nil
    def task_dispatch_block
      candidates = nodes.to_a
      return ["This volume is not assigned to a node.", "node_offline"] if candidates.empty?
      return nil if candidates.any?(&:online?)
      if candidates.any?(&:maintenance)
        ["The node hosting this volume is in maintenance. Backups, restores and exports are paused until it ends.", "node_maintenance"]
      else
        ["The node hosting this volume is offline.", "node_offline"]
      end
    end

    # @param [String] snapshot_name
    # @param [String, nil] task_id pre-minted task id (see #dispatch_task!)
    def create_backup!(snapshot_name, task_id: nil)
      snapshot_name = snapshot_name.strip.tr(" ", "-").delete("$").delete("*")
      return false if name.blank?
      return refuse_dispatch! if task_dispatch_blocker

      snapshot_name = Zaru.sanitize!(snapshot_name)
      selected_node = active_node
      return false if selected_node.nil?

      dispatch_task!(selected_node, name: "volume.backup", archive: snapshot_name, task_id: task_id)
    end

    def delete_backup!(snapshot_name, task_id: nil)
      return false if snapshot_name.blank?
      return refuse_dispatch! if task_dispatch_blocker

      selected_node = active_node
      return false if selected_node.nil?

      dispatch_task!(selected_node, name: "backup.delete", archive: snapshot_name, task_id: task_id)
    end

    def restore_backup!(snapshot_name, source_volume_name = nil, task_id: nil)
      if snapshot_name.blank?
        if current_audit&.event_logs&.exists?
          current_audit.event_logs.first.event_details.create!(
            data: "[Snapshot Restore] Error: Missing snapshot name.",
            event_code: "8715836b24c7898c"
          )
        end
        return false
      end
      return refuse_dispatch!("e747dac60227ea25") if task_dispatch_blocker
      selected_node = active_node
      if selected_node.nil?
        if current_audit&.event_logs&.exists?
          current_audit.event_logs.first.event_details.create!(
            data: "[Snapshot Restore] Error: Missing active node",
            event_code: "7b8fb2202547cc81"
          )
        end
        return false
      end
      dispatch_task!(selected_node, name: "volume.restore", archive: snapshot_name,
        source_volume: source_volume_name.nil? ? name : source_volume_name, task_id: task_id)
    end

    # Export a backup archive to object storage and generate a presigned download URL.
    #
    # Read-only (`borg export-tar --bypass-lock`); does not lock the repo, so it
    # coexists with backups/restores. The agent streams the archive to S3 and reports the
    # presigned URL up the changelog in the `backup.export` task's result.
    #
    # @return [String, false] the task id (jid) on success, false on failure.
    def export_backup!(snapshot_name, task_id: nil)
      return false if snapshot_name.blank?
      return refuse_dispatch! if task_dispatch_blocker

      selected_node = active_node
      return false if selected_node.nil?

      dispatch_task!(selected_node, name: "backup.export", archive: snapshot_name, task_id: task_id)
    end

    private

    # Record why we refused, on the audit's event when there is one, and return false.
    def refuse_dispatch!(event_code = "c41d7e09a2b85f36")
      @dispatch_error, @dispatch_error_code = task_dispatch_block
      if current_audit&.event_logs&.exists?
        current_audit.event_logs.first.event_details.create!(data: @dispatch_error, event_code: event_code)
      end
      false
    end

    # Dispatch a backup-family task to the volume's node via the cs-agent DOWN endpoint.
    #
    # Mint the controller-supplied UUID up front (never a reserved `volume.trash:` form),
    # self-heal the volume's desired-state on the node first (an unconditional idempotent
    # PUT — a volume saved while its node was offline was otherwise never PUT), then POST the
    # task, and return the id.
    #
    # `task_id:` lets a caller pre-mint the id and PERSIST it before dispatching, so a crash
    # between "we decided to dispatch" and "the POST landed" is recoverable: the caller can
    # look the id up in `agent_tasks` to learn whether the POST actually landed, instead of
    # guessing. Used by VolumeServices::CloneStepService; every other caller passes nil and
    # gets the historical mint-here behavior.
    #
    # NB: this deliberately does NOT write the id to `Audit#raw_data`. That column is
    # `serialize`d and rendered by Audit#formatted_name -> AuditHelper#audit_description, so
    # writing a YAML *string* into it made every backup's audit line read
    # "Me updated ---\n:task_id: ...". Nothing ever read it back — correlation is by the
    # `task_id` label on the EventLog (Agent::TaskReconciler#correlated_event).
    #
    # @return [String, false] the task id on success (truthy — existing boolean callers keep
    #   working), false on failure.
    def dispatch_task!(selected_node, name:, archive:, source_volume: nil, task_id: nil)
      jid = task_id.presence || SecureRandom.uuid

      # Self-heal: ensure the node has this volume's desired-state before the task lands.
      # Abort if it fails — the agent's backup handler treats an unknown volume as a skip and
      # marks the task completed, which would falsely report a backup that never ran.
      return false unless Agent::Client.for_node(selected_node).put_volume(agent_project_id.to_s, self.name, default_consul_data)

      params = {source_volume: source_volume || self.name}

      ok = Agent::Client.for_node(selected_node).create_task({
        id: jid,
        project_id: agent_project_id.to_s,
        name: name,
        node: selected_node.hostname,
        volume: self.name,
        archive: archive,
        audit_id: current_audit&.id,
        params: params
      })

      ok ? jid : false
    end
  end
end
