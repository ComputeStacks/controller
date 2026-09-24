##
# volumes:audit_mounts — find template volumes whose bind never landed inside a container.
#
# WHY THIS EXISTS
#
# `Admin::ContainerImages::VolumeParamsController#create` used to gate its cascade on
# `if volume_params[:cascade_changes]`. Rails' `check_box` emits a hidden `"0"` companion and
# `"0"` is truthy in Ruby, so the cascade fired on EVERY volume-param create from the admin
# path — and the worker it dispatched created the `Volume`, the owner `VolumeMap` and the real
# docker volume without ever rebuilding a container. Docker bakes binds at container-create
# time, so the mount cannot appear in a container that already exists.
#
# The result is a volume that looks completely healthy in the UI: row present, map present,
# docker volume present on the node, `borg_enabled` already pushed to the agent — while the
# agent runs its scheduled borg backups against an EMPTY volume and builds a plausible archive
# series containing none of the customer's data. Nobody notices until a restore.
#
# The `volumes.awaiting_mount` column added alongside this task suppresses that (the agent is
# told `backup: false` while it is set), but a plain `default: false` migration marks every
# pre-existing casualty "mounted" and the rebuilt cascade's duplicate checks then skip them
# forever. This task is how those rows are found before that happens.
#
# USAGE
#
#   rake volumes:audit_mounts            # report only (default)
#   rake volumes:audit_mounts FIX=1      # additionally set awaiting_mount on class (a)
#   rake volumes:audit_mounts LIMIT=0    # list every row instead of capping each class at 25
#
# WHAT IT REPORTS  (candidates = Volume.where(to_trash: false).where.not(template_id: nil))
#
#   (a) MAPPED BUT NOT MOUNTED — has an owner map, and no container of the mapped service
#       carries the bind. This is the silently-unbacked-up set, and the only class FIX=1
#       touches.
#   (b) ORPHANS — `template_id` set, no `volume_maps` at all. One per failed retry of the old
#       worker, which died on a `NameError` after the volume was created. Each got
#       `detached_at` stamped by `Volume after_commit :set_detached`, so
#       `BillingUsageServices::CollectUsageService#offline_storage` minted a phantom
#       "Detached Volume" subscription for it — reported here so those are visible.
#   (c) DUPLICATE MAPS — any `(container_service_id, mount_path)` pair with more than one row.
#       Each one is a service Docker will refuse to rebuild (`Duplicate mount point`, which
#       `build!` does not rescue) and it blocks the unique index on `volume_maps`.
#   (d) UNDETERMINED — the mount state could not be established, because the volume's node is
#       offline, was never recorded, or answered the sweep with zero containers. An
#       unreachable node means "no data", NOT "not mounted": `Node#list_all_containers`
#       rescues everything and returns `[]`, so a silent node would otherwise turn its entire
#       volume population into false class (a) hits and FIX=1 would disable backups on live
#       customer data. These are always reported, never fixed.
#
# Only (a) is remediated, and only with `awaiting_mount = true` via `update!` — the
# `after_commit :update_consul!` push is the point: it tells the agent `backup: false` and
# stops the bogus schedule immediately. Trashing orphan volumes and reversing billing rows is
# the operator's decision, not a task's.
#
# The node sweep is ONE `list_all_containers` per online node, inverted into a
# volume-name → mounts index. `Volumes::VolumeLookup.inspect_volume_by_name` scans every
# container on every online node PER CALL, so using it per volume would be
# O(volumes x nodes x containers) against a production fleet. Do not reintroduce it here.
#
module VolumeMountAudit
  # One docker mount observed on a node during the sweep.
  Mount = Struct.new(:node_id, :container_name, :mount_path, keyword_init: true)

  class Auditor
    DEFAULT_LIMIT = 25

    # Class (a): volumes to remediate. Array of [volume, maps].
    attr_reader :unmounted
    # Class (b): [volume, ...]
    attr_reader :orphans
    # Class (c): [[service_id, mount_path, [maps]], ...]
    attr_reader :duplicates
    # Class (d): [[volume, reason], ...]
    attr_reader :undetermined
    # Fine: [[volume, mounts]], where a container of the mapped service carries the bind.
    attr_reader :mounted
    # Mounted by something that is NOT a container of the mapped service (an SFTP container,
    # or a container the controller does not know about). Reported, never fixed — the bind
    # exists on disk, so suppressing backups here could hide real data.
    attr_reader :mounted_elsewhere
    # Volumes whose awaiting_mount was flipped by FIX=1.
    attr_reader :fixed

    # Class (a) splits in two, and the difference matters to a reader: a row already carrying
    # `awaiting_mount` is a cascade in flight (expected, agent already told backup: false),
    # while an unflagged one is the old bug's damage — the agent is archiving an empty volume.
    # Only the unflagged rows are remediated; `update!` on an already-true row would be a no-op
    # anyway, but counting them as "fixed" would misreport the size of the problem.
    #
    # @return [Array<Array(Volume, Array<VolumeMap>)>]
    def unflagged_unmounted
      @unmounted.reject { |(volume, _maps)| volume.awaiting_mount }
    end

    # @return [Array<Array(Volume, Array<VolumeMap>)>]
    def flagged_unmounted
      @unmounted.select { |(volume, _maps)| volume.awaiting_mount }
    end

    # @param out [IO] where the report goes
    # @param fix [Boolean] apply the class (a) remediation
    # @param limit [Integer] per-class listing cap; 0 lists everything
    # @param nodes [Array<Node>, nil] nodes to sweep; defaults to Node.online. Injectable so a
    #   test can drive classification without a docker daemon.
    # @param container_lister [Proc, nil] node → containers responding to #info; defaults to
    #   Node#list_all_containers.
    def initialize(out: $stdout, fix: false, limit: DEFAULT_LIMIT, nodes: nil, container_lister: nil)
      @out = out
      @fix = fix
      @limit = limit.to_i
      @nodes = nodes || Node.online.to_a
      @container_lister = container_lister || ->(node) { node.list_all_containers }

      @unmounted = []
      @orphans = []
      @duplicates = []
      @undetermined = []
      @mounted = []
      @mounted_elsewhere = []
      @fixed = []
      @fix_failures = []

      @mount_index = {}
      @responded_node_ids = []
      @silent_node_ids = []
      @failed_node_ids = []
      @candidate_count = 0
      @container_count = 0
      @mount_count = 0
    end

    def perform
      preamble
      build_mount_index
      classify_candidates
      load_duplicates
      report
      apply_fix if @fix
      summary
      self
    end

    private

    # --- sweep ------------------------------------------------------------------------

    ##
    # One pass per node: volume name → every container mount of it. A node that raises, or
    # that answers with zero containers (which is what Node#list_all_containers returns when
    # the docker API is unreachable — it rescues and returns []), is recorded as NOT having
    # responded, so every volume of its is UNDETERMINED rather than "unmounted".
    def build_mount_index
      say "Sweeping #{@nodes.size} node(s) for container mounts..."
      @nodes.each do |node|
        containers = begin
          Array(@container_lister.call(node))
        rescue => e
          @failed_node_ids << node.id
          say "  [warn] #{node_desc(node.id)}: #{e.class}: #{e.message} — its volumes are UNDETERMINED"
          next
        end

        if containers.empty?
          @silent_node_ids << node.id
          say "  [warn] #{node_desc(node.id)}: reported 0 containers (unreachable docker API, or genuinely empty)"
          say "         — its volumes are UNDETERMINED, never class (a)"
          next
        end

        @responded_node_ids << node.id
        @container_count += containers.size
        containers.each { |c| index_container(node, c) }
      end
      say "  indexed #{@mount_count} mount(s) across #{@container_count} container(s) " \
          "on #{@responded_node_ids.size} responding node(s)"
      say ""
    end

    def index_container(node, container)
      info = container.info || {}
      name = Array(info["Names"]).first.to_s.split("/").last
      Array(info["Mounts"]).each do |mount|
        volume_name = mount["Name"]
        next if volume_name.blank?
        @mount_count += 1
        (@mount_index[volume_name] ||= []) << Mount.new(
          node_id: node.id,
          container_name: name,
          mount_path: mount["Destination"]
        )
      end
    end

    # --- classification ---------------------------------------------------------------

    def candidates
      Volume.where(to_trash: false).where.not(template_id: nil)
        .includes(:nodes, :deployment, volume_maps: {container_service: [:containers, :deployment]})
    end

    def classify_candidates
      candidates.find_in_batches(batch_size: 250) do |batch|
        # One AgentRepository query per batch instead of one per volume, so the archive count
        # in the report is free.
        Volume.prime_repo_info!(batch)
        batch.each { |volume| classify volume }
      end
    end

    def classify(volume)
      @candidate_count += 1
      maps = volume.volume_maps.to_a
      return @orphans << volume if maps.empty?

      services = maps.filter_map(&:container_service)
      service_container_names = services.flat_map { |s| s.containers.map(&:name) }
      mounts = @mount_index.fetch(volume.name, [])
      own = mounts.select { |m| service_container_names.include?(m.container_name) }

      if own.any?
        @mounted << [volume, own]
      elsif mounts.any?
        @mounted_elsewhere << [volume, mounts]
      else
        reason = undetermined_reason(volume, services)
        if reason
          @undetermined << [volume, reason]
        else
          @unmounted << [volume, maps]
        end
      end
    end

    ##
    # Why we cannot trust "no container mounts this volume", or nil when we can.
    #
    # Trustworthy means: every node this volume could live on answered the sweep with a real
    # container list. Anything else is ignorance, and ignorance must never be reported as
    # class (a) — FIX=1 would then push `backup: false` for a volume that is mounted and full
    # of customer data.
    def undetermined_reason(volume, services)
      node_ids = volume.nodes.map(&:id)
      if node_ids.empty?
        # No nodes_volumes rows (older volumes, or a partially-provisioned one) — fall back to
        # wherever the mapped services' containers actually live.
        node_ids = services.flat_map { |s| s.containers.map(&:node_id) }.compact.uniq
      end
      if node_ids.empty?
        return "no node recorded for this volume and its service(s) have no containers"
      end

      unanswered = node_ids.reject { |id| @responded_node_ids.include?(id) }
      return nil if unanswered.empty?

      reason = unanswered.map { |id| node_state(id) }.join("; ")
      if services.any? && services.all? { |s| s.containers.empty? }
        reason += " (note: no container rows exist for its service(s) either, so it is " \
                  "probably genuinely unmounted — verify by hand)"
      end
      reason
    end

    def node_state(id)
      if @silent_node_ids.include?(id)
        "#{node_desc(id)} reported 0 containers"
      elsif @failed_node_ids.include?(id)
        "#{node_desc(id)} errored during the sweep"
      elsif @nodes.none? { |n| n.id == id }
        "#{node_desc(id)} is offline or in maintenance (excluded from Node.online)"
      else
        "#{node_desc(id)} was not swept"
      end
    end

    # --- duplicates -------------------------------------------------------------------

    def load_duplicates
      pairs = VolumeMap.where.not(container_service_id: nil)
        .group(:container_service_id, :mount_path)
        .having("count(*) > 1").count
      return if pairs.empty?

      pairs.each_key do |(service_id, mount_path)|
        maps = VolumeMap.where(container_service_id: service_id, mount_path: mount_path)
          .includes(:volume, container_service: :deployment).order(:id).to_a
        @duplicates << [service_id, mount_path, maps]
      end
    end

    # --- report -----------------------------------------------------------------------

    def preamble
      say "=" * 78
      say "volumes:audit_mounts — #{@fix ? "FIX MODE (class (a) will be modified)" : "report only"}"
      say "=" * 78
      unless @fix
        say "Pass FIX=1 to set awaiting_mount on class (a) and stop the bogus backup schedule."
      end
      say ""
    end

    def report
      report_unmounted
      report_orphans
      report_duplicates
      report_undetermined
      report_mounted_elsewhere
    end

    def report_unmounted
      say "(a) MAPPED BUT NOT MOUNTED — #{@unmounted.size} volume(s)" \
        " (#{unflagged_unmounted.size} unflagged, #{flagged_unmounted.size} already awaiting_mount)"
      say "    Volume row, owner VolumeMap and docker volume all exist, but no container of"
      say "    the mapped service carries the bind."
      say ""
      say "    awaiting_mount=true rows are EXPECTED and healthy: a cascade attached the volume"
      say "    and it mounts at the service's next rebuild. The agent is already told"
      say "    backup: false for those, so nothing is archiving an empty volume."
      say ""
      say "    awaiting_mount=false rows with agent_backup=ON are the damage: the agent has been"
      say "    archiving an EMPTY volume. Those #{unflagged_unmounted.size} are what FIX=1 remediates."
      return say_none if @unmounted.empty?

      each_capped(@unmounted, group_by: ->((volume, maps)) { group_key(volume, maps) }) do |(volume, maps)|
        owner = owner_map(maps)
        say "      vol #{volume.id}  #{volume_line(volume)}  path=#{owner&.mount_path.inspect}"
      end
      say ""
    end

    def report_orphans
      say "(b) ORPHANS (template_id, no volume_maps) — #{@orphans.size} volume(s)"
      say "    One per failed retry of the old cascade worker. detached_at was stamped on each,"
      say "    which minted a phantom \"Detached Volume\" subscription. NOT auto-fixed —"
      say "    trashing volumes and reversing billing rows is your call, not this task's."
      return say_none if @orphans.empty?

      each_capped(@orphans, group_by: ->(volume) { project_label(volume.deployment) }) do |volume|
        say "      vol #{volume.id}  #{volume_line(volume)}  template=#{volume.template_id}  " \
            "detached_at=#{volume.detached_at&.iso8601 || "-"}  subscription=#{volume.subscription_id || "-"}"
      end
      say ""
    end

    def report_duplicates
      say "(c) DUPLICATE VOLUME MAPS — #{@duplicates.size} (container_service_id, mount_path) pair(s)"
      say "    Each pair is a service Docker will refuse to rebuild (two binds, one destination"
      say "    → 400 Duplicate mount point, which build! does not rescue) and it blocks the"
      say "    unique index on volume_maps. NOT auto-fixed: which map to keep is your call, and"
      say "    VolumeMap#ensure_not_primary blocks deleting an is_owner map through the UI."
      return say_none if @duplicates.empty?

      each_capped(@duplicates) do |(service_id, mount_path, maps)|
        service = maps.first&.container_service
        say "    service #{service_id} #{service&.label.inspect} " \
            "(project #{project_label(service&.deployment)})  path=#{mount_path.inspect}"
        maps.each do |m|
          say "      map #{m.id}  volume #{m.volume_id} #{m.volume&.label.inspect}  is_owner=#{m.is_owner}"
        end
      end
      say ""
    end

    def report_undetermined
      say "(d) UNDETERMINED — #{@undetermined.size} volume(s)"
      say "    The mount state could not be established. An unreachable node means \"no data\","
      say "    not \"not mounted\", so these are deliberately NOT class (a) and FIX=1 leaves"
      say "    them alone. Bring the node back and re-run."
      return say_none if @undetermined.empty?

      each_capped(@undetermined, group_by: ->((volume, _)) { group_key(volume, volume.volume_maps.to_a) }) do |(volume, reason)|
        say "      vol #{volume.id}  #{volume_line(volume)}"
        say "        reason: #{reason}"
      end
      say ""
    end

    def report_mounted_elsewhere
      return if @mounted_elsewhere.empty?
      say "(note) MOUNTED BY A CONTAINER THAT IS NOT PART OF THE MAPPED SERVICE — " \
          "#{@mounted_elsewhere.size} volume(s)"
      say "    Typically the SFTP container. The application's own containers do not carry the"
      say "    bind, but the data may well be real, so this is reported and never fixed."
      each_capped(@mounted_elsewhere) do |(volume, mounts)|
        say "      vol #{volume.id}  #{volume_line(volume)}"
        mounts.each { |m| say "        #{node_desc(m.node_id)} container=#{m.container_name} at #{m.mount_path}" }
      end
      say ""
    end

    # --- remediation ------------------------------------------------------------------

    def apply_fix
      say "-" * 78
      if unflagged_unmounted.empty?
        say "FIX=1: nothing to do — no class (a) volume needs flagging" \
          "#{" (#{flagged_unmounted.size} already awaiting_mount)" unless flagged_unmounted.empty?}."
        say ""
        return
      end
      say "FIX=1: setting awaiting_mount = true on #{unflagged_unmounted.size} volume(s)."
      say "       update! (not update_columns) is deliberate — the after_commit :update_consul!"
      say "       push is what tells the agent backup: false and stops the schedule now."
      unflagged_unmounted.each do |(volume, _maps)|
        volume.update!(awaiting_mount: true)
        @fixed << volume
        say "  [fixed] vol #{volume.id} (#{volume.name}) #{volume.label.inspect} — agent told backup: false"
      rescue => e
        @fix_failures << [volume, e]
        say "  [fail]  vol #{volume.id} (#{volume.name}): #{e.class}: #{e.message}"
      end
      say ""
    end

    # --- summary ----------------------------------------------------------------------

    def summary
      say "=" * 78
      say "Candidates examined: #{@candidate_count} " \
          "(Volume.where(to_trash: false).where.not(template_id: nil))"
      say "  (a) mapped but not mounted : #{@unmounted.size} " \
          "(#{unflagged_unmounted.size} unflagged, #{flagged_unmounted.size} already awaiting_mount)"
      say "  (b) orphans, no map        : #{@orphans.size}"
      say "  (c) duplicate map pairs    : #{@duplicates.size}"
      say "  (d) undetermined           : #{@undetermined.size}"
      say "  ok, mounted                : #{@mounted.size}"
      say "  mounted elsewhere only     : #{@mounted_elsewhere.size}" unless @mounted_elsewhere.empty?

      if @fix
        say ""
        say "Changed: #{@fixed.size} volume(s) now awaiting_mount = true."
        say "Failed to change: #{@fix_failures.size} volume(s)." if @fix_failures.any?
        say "Left alone: (b) #{@orphans.size}, (c) #{@duplicates.size}, (d) #{@undetermined.size} " \
            "— reported only, by design."
      elsif unflagged_unmounted.any?
        say ""
        say "Re-run with FIX=1 to set awaiting_mount on the #{unflagged_unmounted.size} " \
            "unflagged class (a) volume(s)."
      end

      if nothing_to_do?
        say ""
        say "Nothing to do — no volume is in a broken mount state."
      end
      say "=" * 78
    end

    def nothing_to_do?
      @unmounted.empty? && @orphans.empty? && @duplicates.empty? &&
        @undetermined.empty? && @mounted_elsewhere.empty?
    end

    # --- formatting helpers -----------------------------------------------------------

    ##
    # Print at most @limit items (0 = all), optionally grouped, and SAY SO when truncated —
    # a silent cap on a fleet audit is how an operator concludes "only 25 volumes are broken".
    def each_capped(items, group_by: nil)
      shown = (@limit.zero? || @limit >= items.size) ? items : items.first(@limit)
      if group_by
        shown.group_by { |i| group_by.call(i) }.each do |heading, group|
          say "  #{heading}"
          group.each { |i| yield i }
        end
      else
        shown.each { |i| yield i }
      end
      if shown.size < items.size
        say "    ... and #{items.size - shown.size} more not listed " \
            "(#{items.size} total; re-run with LIMIT=0 to list all)"
      end
    end

    def group_key(volume, maps)
      owner = owner_map(maps)
      service = owner&.container_service
      project = service&.deployment || volume.deployment
      "project #{project_label(project)} / service #{service ? "#{service.id} #{service.label.inspect}" : "(none)"}"
    end

    def owner_map(maps)
      maps.detect(&:is_owner) || maps.first
    end

    def project_label(deployment)
      return "(none)" if deployment.nil?
      "#{deployment.id} #{deployment.name.inspect}"
    end

    # borg_enabled is what the operator set; agent_backup is what the agent was actually told
    # (Volumes::ConsulVolume#default_consul_data gates it on !awaiting_mount). archives is the
    # number the agent has already produced — on a class (a) volume every one of them is empty.
    def volume_line(volume)
      archives = Array(volume.repo_info["archives"]).size
      "#{volume.label.inspect}  borg=#{volume.borg_enabled ? "on" : "off"}  " \
        "agent_backup=#{(volume.borg_enabled && !volume.awaiting_mount) ? "ON" : "off"}  " \
        "archives=#{archives}  " \
        "awaiting_mount=#{volume.awaiting_mount}  name=#{volume.name}"
    end

    def node_desc(id)
      node = node_cache[id]
      node ? "node #{id} (#{node.label})" : "node #{id} (unknown)"
    end

    def node_cache
      @node_cache ||= Node.all.index_by(&:id)
    end

    def say_none
      say "    none"
      say ""
    end

    def say(line)
      @out.puts line
    end
  end
end

namespace :volumes do
  desc "Audit template volumes for binds that never landed in a container (the broken " \
       "cascade's damage): reports mapped-but-unmounted, orphan, duplicate-map and " \
       "undetermined volumes. FIX=1 sets awaiting_mount on the mapped-but-unmounted set only, " \
       "which tells the agent backup: false and stops it archiving an empty volume. " \
       "LIMIT=n caps each class's listing (default 25, 0 = all). Read-only without FIX=1."
  task audit_mounts: :environment do
    # The report reads `awaiting_mount` on every row and FIX=1 writes it, so the column has to
    # be there. It ships in its own migration (20260803000001) precisely so it lands even when
    # the unique-index migration behind it refuses to run — but say so plainly rather than
    # dying on a NoMethodError half way through a report.
    unless Volume.column_names.include?("awaiting_mount")
      abort <<~MSG
        volumes:audit_mounts needs the `volumes.awaiting_mount` column, which is not present.

        Run `rails db:migrate` first. Migration 20260803000001 adds the column and is
        unconditional; 20260803000002 (the unique index on volume_maps) is the one that can
        refuse, and this task is what tells you which duplicate maps are blocking it.
      MSG
    end

    # ActiveModel cast, not truthiness: `FIX=0` must mean off. Getting this wrong on a
    # check_box param is what created the damage this task exists to find.
    fix = ActiveModel::Type::Boolean.new.cast(ENV["FIX"])
    limit = ENV["LIMIT"].present? ? ENV["LIMIT"].to_i : VolumeMountAudit::Auditor::DEFAULT_LIMIT
    VolumeMountAudit::Auditor.new(fix: fix, limit: limit).perform
  end
end
