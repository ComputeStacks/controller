module Volumes
  # NB: kept the historical name Volumes::ConsulVolume (cosmetic) through the Consul
  # retirement. Volume desired-state, backup-repo info, and export status now flow over the
  # cs-agent HTTP data channel (Agent::Client + the changelog projections AgentRepository /
  # AgentTask), not Consul KV.
  module ConsulVolume
    extend ActiveSupport::Concern

    class_methods do
      # Resolve every volume's backup repository in ONE query and seed each memo.
      #
      # For any list view that touches `list_archives` / `backup_usage` per row. Volumes
      # without a repository row are primed to `{}` too, so they don't fall back to a lookup.
      #
      # @param [Enumerable<Volume>] volumes
      # @return [Enumerable<Volume>] the same collection
      def prime_repo_info!(volumes)
        names = volumes.filter_map(&:name)
        repos = names.empty? ? {} : AgentRepository.where(name: names).index_by(&:name)
        volumes.each { |v| v.prime_repo_info! repos[v.name] }
        volumes
      end
    end

    # Compressed Backup Size
    #
    # Deduplicated and compressed size
    def backup_usage
      info = repo_info
      return 0.0 if info.empty?
      return 0.0 unless info["usage"]
      (info["usage"] / BYTE_TO_GB).round(4)
    end

    # Total size of backup
    #
    # When uncompressed, this will be the total size on disk
    def backup_total_usage
      info = repo_info
      return 0.0 if info.empty?
      return 0.0 unless info["usage"]
      return 0.0 if info["size"].nil?
      (info["size"] / BYTE_TO_GB).round(4)
    end

    # List all backups for a Volume
    #
    # Reads the archive list from the projected repository row.
    #
    # @example
    #     [{ id: integer, label: string, created: date }]
    #
    def list_archives
      return [] if repo_info.empty?
      list = []
      archives = repo_info["archives"]
      return list if archives.nil?
      archives.reverse_each do |i|
        id = Base64.urlsafe_encode64(i)
        split_name = i.split("auto-")
        split_name = i.split("-m-") if split_name.count == 1
        if split_name.count > 1
          begin
            ts = Time.parse("#{split_name.last} UTC")
            list << {
              id: id,
              label: (split_name.first == "") ? "auto" : split_name.first,
              created: ts
            }
          rescue
            list << {id: id, label: i}
          end
        else
          list << {id: id, label: i}
        end
      end
      list
    end

    # The newest archive that carries a parseable timestamp, or nil.
    #
    # `list_archives` deliberately omits `:created` for names it cannot parse (a manually
    # created archive, or one whose timestamp fails Time.parse), so a naive
    # `sort_by { |a| a[:created] }` raises `ArgumentError: comparison of NilClass with Time
    # failed` as soon as ONE such archive exists in the repo. Filter first.
    #
    # @return [Hash, nil]
    def latest_archive
      list_archives.select { |a| a[:created] }.max_by { |a| a[:created] }
    end

    # Find the RAW borg archive name created for a given label.
    #
    # The agent names an archive "<label>-m-<timestamp>" — we choose the label, it chooses the
    # suffix — so a caller that requested a backup under a known label can only recover the
    # full name by searching the projected repository. Returns the raw string (what
    # #restore_backup! and #delete_backup! want); do NOT round-trip it through Base64, and
    # persist it once found: `agent_repositories.archives` is a snapshot upsert, so agent-side
    # borg retention can prune the archive out from under a later read.
    #
    # @param [String] label
    # @return [String, nil]
    def find_archive_by_label(label)
      return nil if label.blank?
      archives = repo_info["archives"]
      return nil unless archives.is_a?(Array)
      archives.reverse.detect { |n| n.to_s.start_with?("#{label}-m-") }
    end

    # Drop the memoized repository snapshot so the next read re-queries agent_repositories.
    #
    # Required by any caller that forces an Agent::ChangelogProjector pass and must observe the
    # newly-projected archive list on the SAME object. This is exactly the bug that broke
    # project clone: the old CloneVolumeService warmed the memo before requesting the backup
    # and then polled the frozen copy for 300s, so the archive it was waiting for could never
    # appear. The memo itself is kept — Api::Volumes::BackupsController reads repo_info three
    # times per request on one object.
    #
    # @return [Volume] self, so it can be chained.
    def reset_repo_info!
      @repo_info = nil
      self
    end

    # View info about a volume's backup repository.
    #
    # Reads the projected `AgentRepository` row (the changelog-mirrored borg repo state that
    # replaces the old Consul `borg/repository/<name>` read). The hash SHAPE is unchanged so
    # the existing consumers (backup_usage, list_archives, container_usage, volume_helper)
    # keep working: empty `{}` when there is no repository row yet.
    #
    # @example
    #   {
    #     "usage"=>18522047, # Size on disk (deduplicated)
    #     "size"=>95738056,  # Actual total size
    #     "archives"=> ["auto-2019-08-29T07:01:55-m-2019-08-29T07:01:55", ...]
    #   }
    def repo_info
      @repo_info ||= repo_info_from(AgentRepository.find_by(name: name))
    end

    # Seed the memo from an already-loaded AgentRepository (or nil for "no repository row").
    #
    # `repo_info` looks its row up by NAME, not through an association, so `includes` cannot
    # preload it and a list view rendering `list_archives.count` per row costs one query per
    # volume. Volume.prime_repo_info! resolves the whole page in one.
    #
    # @param [AgentRepository, nil] repo
    # @return [Volume] self
    def prime_repo_info!(repo)
      @repo_info = repo_info_from(repo)
      self
    end

    # Resolve the current download state for each archive that has an export event.
    #
    # One SQL query (export events, newest first) correlated to the export task's projected
    # result (agent_tasks.result). Keyed by the borg archive name stored in the event's
    # labels["archive"].
    #
    # @return [Hash] { archive_name => { status:, url:, expires_at:, size: } }
    #   status is one of: in_progress, ready, expired, failed.
    def export_status_map
      event_logs.where(event_code: EventLog::BACKUP_EXPORT_EVENT_CODE)
        .order(created_at: :desc)
        .each_with_object({}) do |event, acc|
          archive = event.labels["archive"]
          next if archive.blank? || acc.key?(archive)
          acc[archive] = resolve_export_state(event)
        end
    end

    ##
    # Push (upsert) this volume's desired-state to its node's cs-agent. Replaces the old
    # Consul `volumes/<name>` KV write. Idempotent — the agent begins/continues scheduling
    # backups from it. Node/volume labels are cosmetic; addressing goes through for_node.
    def update_consul!
      return true if nodes.empty?
      return true if nodes.online.empty?
      node = active_node
      return true if node.nil?
      # Agent::Client#put_volume is transport-tolerant (returns false, never raises).
      Agent::Client.for_node(node).put_volume(agent_project_id.to_s, name, default_consul_data)
    end

    ##
    # Determine the currently-assigned node for this volume (the node its backups run on).
    # Replaces the KV-read `consul_active_node`; resolves via `consul_select_node`.
    # @return [Node, nil]
    def active_node
      hostname = consul_select_node
      hostname.blank? ? nil : Node.find_by(hostname: hostname)
    rescue => e
      ExceptionAlertService.new(e, "e69441ff0f3f4a0c").perform
      nil
    end

    private

    # The hash SHAPE the rest of this concern consumes. One builder, so `repo_info` and
    # `prime_repo_info!` can never drift apart.
    def repo_info_from(repo)
      return {} if repo.nil?
      {"usage" => repo.size_on_disk, "size" => repo.total_size, "archives" => repo.archives}
    end

    # Resolve a single export event into a UI/API state hash. A presigned URL is only
    # surfaced when the correlated `backup.export` task completed with an https url and an
    # unexpired expiry (this method — not the view — is the source of truth for that
    # validation). The URL/expiry/size come from the export task's projected `result`
    # ({url, object_key, size, expiry}), correlated via the event's `task_id` label.
    def resolve_export_state(event)
      return {status: "in_progress"} if event.active?
      return {status: "failed", error: event.state_reason} if event.failed?
      return {status: "expired"} unless event.success?

      task_id = event.labels["task_id"]
      task = task_id.present? ? AgentTask.find_by(id: task_id) : nil
      result = task&.result
      if result.is_a?(Hash) &&
          task.status == "completed" &&
          result["url"].to_s.start_with?("https://") &&
          result["expiry"].to_i > Time.now.to_i
        {
          status: "ready",
          url: result["url"],
          expires_at: result["expiry"].to_i,
          size: result["size"]
        }
      else
        {status: "expired"}
      end
    end

    # The volume desired-state PUT to the agent (was the Consul `volumes/<name>` value).
    # `last_backup` is intentionally omitted — the agent ignores a DOWN last_backup (freshness
    # comes only from a completed volume.backup task result). `project_id` is the sentinel-aware
    # value so detached volumes render "0" consistently across the URL path, task body, and this
    # config int.
    #
    # `backup` is gated on `!awaiting_mount` HERE rather than at any call site, and that
    # placement is load-bearing: every path that pushes desired-state to the agent funnels
    # through this hash — `Volume after_commit :update_consul!`, the container start/stop/
    # restart workers, `Volumes::BackupVolume#dispatch_task!`'s self-heal PUT before a task,
    # and the mount-audit backfill rake task. Gating in one call site would leave the others
    # free to re-enable scheduled borg backups on a volume no container has mounted yet,
    # which produces a healthy-looking archive series of an empty volume — the single worst
    # outcome this feature can cause. There is deliberately no way to bypass it.
    def default_consul_data
      {
        id: id,
        name: name,
        node: consul_select_node,
        backup: (borg_enabled && !awaiting_mount),
        freq: borg_freq,
        retention: {
          keep_hourly: borg_keep_hourly,
          keep_daily: borg_keep_daily,
          keep_weekly: borg_keep_weekly,
          keep_monthly: borg_keep_monthly,
          keep_annually: borg_keep_annually
        },
        project_id: agent_project_id,
        service_id: container_service&.id,
        trash: to_trash,
        strategy: borg_strategy,
        backup_error_cont: borg_backup_error,
        restore_error_cont: borg_restore_error,
        pre_backup: borg_pre_backup,
        post_backup: borg_post_backup,
        pre_restore: borg_pre_restore,
        post_restore: borg_post_restore,
        rollback_restore: borg_rollback
      }
    end

    # Determine which node should initiate backups
    def consul_select_node
      if container_service.nil? || containers.empty?
        return "" if nodes.online.empty?
        nodes.online.first.hostname
      else
        n = nil
        containers.each do |c|
          next if c.node.nil?
          n = c.node if c.node.online?
          break unless n.nil?
        end
        n.nil? ? "" : n.hostname
      end
    end
  end
end
