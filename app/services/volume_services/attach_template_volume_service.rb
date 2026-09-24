module VolumeServices
  ##
  # Attach an image volume template to ONE already-deployed container service.
  #
  # The unit of work behind the image volume-param cascade: an admin adds a volume to a
  # container image and we create the `Volume` row, its owner `VolumeMap` and the real docker
  # volume on the node for every service already running that image — without rebuilding or
  # restarting anything. Docker bakes binds at container-create time
  # (`Containers::ContainerRuntime#runtime_config`), so the mount only appears inside the
  # containers at the service's next natural rebuild. Until then the volume carries
  # `awaiting_mount: true`, which suppresses borg backups (see
  # `Volumes::ConsulVolume#default_consul_data`) so the agent can't build a healthy-looking
  # archive series of an empty volume.
  #
  # Contract:
  #   * `#perform` returns `:created`, `:skipped` or `:failed` and NEVER raises.
  #   * `#message` is one human-readable line describing what happened.
  #   * Idempotent: safe to re-run any number of times. Re-running is the supported recovery
  #     path for a worker killed part way through, which is why the skip branches verify and
  #     heal the node side rather than returning early on the DB state alone.
  #
  # @!attribute volume_param
  #   @return [ContainerImage::VolumeParam]
  # @!attribute service
  #   @return [Deployment::ContainerService]
  # @!attribute event
  #   @return [EventLog]
  class AttachTemplateVolumeService
    CREATED_EVENT_CODE = "cec9279b879933df".freeze
    SKIPPED_EVENT_CODE = "745cbc9c16461690".freeze
    FAILED_EVENT_CODE = "9027d6b6be37caf0".freeze
    EXCEPTION_EVENT_CODE = "e52b28ce426d3656".freeze

    attr_accessor :volume_param,
      :service,
      :event

    # @return [String] one human readable line, populated by #perform
    attr_reader :message

    # @return [Volume, nil] the volume created by this run
    attr_reader :volume

    # @return [VolumeMap, nil] the owner map created by this run
    attr_reader :volume_map

    # @param [ContainerImage::VolumeParam] volume_param
    # @param [Deployment::ContainerService] container_service
    # @param [EventLog] event
    def initialize(volume_param, container_service, event)
      self.volume_param = volume_param
      self.service = container_service
      self.event = event
      @message = ""
      @volume = nil
      @volume_map = nil
      @target_nodes = []
      @provision_error = nil
    end

    # @return [Symbol] :created, :skipped or :failed
    def perform
      # 1. Ineligible input.
      return skipped!("volume template is a reference to another volume, which is never cascaded") if volume_param.source_volume.present?
      return skipped!("volume template has no mount path") if volume_param.mount_path.blank?
      # `belongs_to :deployment` is required on Deployment::ContainerService, so there is no
      # nil project to guard. Mirrors Authorization::ContainerService#can_view?.
      project = service.deployment
      return skipped!("project is being deleted") if project.status == "deleting" || project.deleting?

      # 2. Normalise exactly as VolumeMap's before_validation does. Querying on the raw
      # mount_path would let a duplicate slip past the checks below and then explode on the
      # unique index.
      normalized = VolumeMap.safe_mount(volume_param.mount_path)

      # 3. Duplicate checks. These query volume_maps, NOT service.volumes: `volumes` is
      # `has_many through: :volume_maps`, so everything it returns already has a map and any
      # "volume exists but has no map" branch built on it would be dead code. Orphan Volume
      # rows with no map are deliberately not adopted here (nothing ties them to a service);
      # `rake volumes:audit_mounts` reports them.
      existing_at_path = service.volume_maps.find_by(mount_path: normalized)&.volume
      if existing_at_path
        # Name the occupant. It is not always a volume anyone chose: VolumeServices::
        # SyncVolumeService imports anonymous docker volumes (an undeclared `VOLUME` in the
        # image) and gives them an owner map at the path docker used, with backups deliberately
        # off. If one of those is sitting where this template wants to be, the cascade skips the
        # service forever and the admin needs to see WHY — the customer's data may be in that
        # imported volume, in which case enabling backups on it is the fix, not creating a
        # second empty one beside it.
        return skipped!(
          "already has a volume mounted at #{normalized} — volume #{existing_at_path.id} " \
          "(#{existing_at_path.label}), template #{existing_at_path.template_id.inspect}, " \
          "backups #{existing_at_path.borg_enabled ? "on" : "OFF"}" \
          "#{heal_node_side(existing_at_path)}"
        )
      end

      from_template = service.volume_maps.joins(:volume)
        .where(volumes: {template_id: volume_param.id}).first&.volume
      if from_template
        return skipped!("already has a volume from this template#{heal_node_side(from_template)}")
      end

      # 4. Node selection. Every target node must be ONLINE: DockerVolumeLocal::Volume#create!
      # and #provisioned? both `next unless node.online?` and return true when every node was
      # skipped, so against an offline node "provisioned" is unfalsifiable and we would commit
      # a volume that exists nowhere.
      driver = service.container_image.force_local_volume ? "local" : service.region.volume_backend
      @target_nodes = (driver == "nfs") ? service.region.nodes.to_a : service.nodes.to_a

      return skipped!("service has no node (not deployed)") if target_nodes.empty?
      offline = target_nodes.reject { |n| n.online? }
      unless offline.empty?
        return skipped!("node #{offline.map(&:hostname).join(", ")} is offline")
      end
      if driver != "nfs" && target_nodes.count > 1
        # Containers::ContainerRuntime#runtime_config filters binds by the CONTAINER's node,
        # so a local volume attached to one node of a multi-node service would give the
        # replicas divergent filesystems.
        return skipped!("service spans multiple nodes and the #{driver} backend is not shared")
      end

      # 5. Build BOTH records unsaved and validate BOTH before writing anything, so a nested
      # mount path (VolumeMap#no_nested_volumes) or a uniqueness conflict becomes a clean
      # reported skip instead of a crash that leaves an orphan Volume behind on every retry.
      @volume = build_volume driver
      @volume_map = service.volume_maps.new(
        volume: volume,
        mount_path: volume_param.mount_path,
        mount_ro: false,
        is_owner: true
      )

      unless volume.valid?
        return skipped!("volume is invalid: #{volume.errors.full_messages.join(" ")}")
      end
      unless volume_map.valid?
        return skipped!("mount is invalid: #{volume_map.errors.full_messages.join(" ")}")
      end

      # 6. ONE transaction, and that is load-bearing. `Volume after_commit :set_detached`
      # then sees a non-empty `container_services` and leaves `detached_at` nil, so the
      # volume never lands in BillingUsageServices::CollectUsageService#offline_storage (which
      # bills detached volumes and opens a "Detached Volume" subscription) while it sits
      # pending -- possibly for weeks. The first `update_consul!` also carries the right
      # `service_id` and `backup: false`.
      begin
        ActiveRecord::Base.transaction do
          volume.save!
          volume_map.save!
        end
      rescue ActiveRecord::RecordNotUnique
        # Lost a race with a concurrent cascade for this same (service, mount_path). The
        # unique index on volume_maps is the authority -- the uniqueness VALIDATION above
        # cannot see a row another transaction has not committed yet. The transaction rolled
        # back, so nothing is left behind (Rails restores the record state of anything saved
        # inside it), and the winner has already done the work. Report the skip it actually
        # is instead of letting it reach the catch-all as a "failure" and page someone.
        return skipped!("another cascade attached this volume concurrently")
      end

      # 7. Create the docker volume on the node, then POSITIVELY assert it is there
      # (meaningful now that every target node is known-online).
      provisioned = begin
        VolumeServices::ProvisionVolumeService.new(volume, event).perform &&
          volume.volume_client.provisioned?
      rescue => e
        @provision_error = e.message
        false
      end

      return rollback!(provision_failure_reason) unless provisioned

      created!
    rescue => e
      ExceptionAlertService.new(e, EXCEPTION_EVENT_CODE).perform
      SystemEvent.create!(
        message: "Error attaching template volume to container service #{service&.id}",
        log_level: "warn",
        data: {
          volume_param: volume_param&.id,
          container_service: service&.id,
          error: e.message
        },
        event_code: EXCEPTION_EVENT_CODE
      )
      failed!("unexpected error: #{e.message}")
    end

    private

    # @return [Array<Node>]
    attr_reader :target_nodes

    # Every borg/sftp attribute is copied from the param exactly as
    # ProvisionServices::ContainerServiceProvisioner#build_volumes! does, so a cascaded
    # volume is indistinguishable from one created at order time apart from `awaiting_mount`.
    #
    # `nodes` is load-bearing three times over: the driver's `create!` iterates it,
    # `runtime_config`'s bind filter matches the container's node against it, and
    # `update_consul!` picks the node it addresses out of it.
    #
    # @param [String] driver
    # @return [Volume]
    def build_volume(driver)
      vol = Volume.new(
        label: volume_param.label,
        user: service.deployment.user,
        deployment: service.deployment,
        borg_enabled: volume_param.borg_enabled,
        borg_freq: volume_param.borg_freq,
        borg_strategy: volume_param.borg_strategy,
        borg_keep_hourly: volume_param.borg_keep_hourly,
        borg_keep_daily: volume_param.borg_keep_daily,
        borg_keep_weekly: volume_param.borg_keep_weekly,
        borg_keep_monthly: volume_param.borg_keep_monthly,
        borg_keep_annually: volume_param.borg_keep_annually,
        borg_backup_error: volume_param.borg_backup_error,
        borg_restore_error: volume_param.borg_restore_error,
        borg_pre_backup: volume_param.borg_pre_backup,
        borg_post_backup: volume_param.borg_post_backup,
        borg_pre_restore: volume_param.borg_pre_restore,
        borg_post_restore: volume_param.borg_post_restore,
        borg_rollback: volume_param.borg_rollback,
        enable_sftp: volume_param.enable_sftp,
        region: service.region,
        volume_backend: driver,
        template: volume_param,
        awaiting_mount: true
      )
      vol.nodes = target_nodes
      vol
    end

    # The resume path for a run that was killed between the DB commit and provisioning: the
    # rows exist, so the duplicate checks above short-circuit, but the docker volume may not.
    # Re-running the cascade therefore repairs the node side instead of reporting a healthy
    # skip over a broken volume.
    #
    # Only attempted when the volume has at least one online node -- `provisioned?` skips
    # offline nodes and returns true, so the answer would be meaningless otherwise.
    #
    # @param [Volume] existing
    # @return [String] a suffix for the skip message ("" when there was nothing to do)
    def heal_node_side(existing)
      return "" if existing.nil? || existing.to_trash
      return "" if existing.nodes.online.empty?
      return "" if existing.volume_client.provisioned?

      if VolumeServices::ProvisionVolumeService.new(existing, event).perform
        "; its docker volume was missing on the node and has been re-provisioned"
      else
        "; its docker volume is missing on the node and could not be re-provisioned"
      end
    rescue => e
      "; unable to verify its docker volume on the node (#{e.message})"
    end

    # The driver's own error strings are unavailable here on purpose: `volume_client` builds a
    # NEW driver object on every call, and the one that collected the errors lives and dies
    # inside ProvisionVolumeService -- which already writes them to this same event as a detail
    # line (event_code 3ace7a0db8fcc88f and friends). So point at that rather than inventing a
    # second, emptier copy.
    #
    # @return [String]
    def provision_failure_reason
      return @provision_error if @provision_error.present?
      "unable to provision the volume on the node (see the preceding event detail for the driver error)"
    end

    # Undo everything. Never leave a mount in a service's config pointing at a volume that is
    # absent from the node: at the next rebuild Docker silently auto-creates the missing
    # volume with the `local` driver and no labels, which is wrong in an NFS region and
    # invisible until a customer notices their data isn't shared or isn't backed up.
    #
    # @param [String] reason
    # @return [Symbol] :failed
    def rollback!(reason)
      project_id = volume.agent_project_id.to_s
      volume_name = volume.name

      # Best effort: `create!` may have succeeded on some nodes before failing on another, and
      # the assertion can fail on a volume that does exist. Nothing here may raise.
      begin
        volume.volume_client.destroy
      rescue
        nil
      end
      target_nodes.each do |node|
        Agent::Client.for_node(node).delete_volume(project_id, volume_name)
      rescue
        nil
      end

      # Raw deletes on purpose. `Volume#before_destroy :ensure_can_trash!` really does abort
      # (throw(:abort)) for a volume that is not already marked for trash, and marking this one
      # for trash to satisfy it would hand it to the trash worker's own teardown for a row that
      # never became real. (`VolumeMap#before_destroy :ensure_not_primary` looks like a second
      # obstacle but is not one: it adds an error and returns false, which has not halted a
      # callback chain since Rails 5 — verified, an owner map destroys fine.)
      volume.nodes.delete_all if volume.persisted? # join rows only; delete_all below skips dependents
      # Same reason: `has_many :audits, dependent: :nullify` never fires for a raw delete, and
      # Auditable already wrote a create row for the volume we are about to remove. Nullify it
      # by hand so AuditHelper#audit_description isn't left resolving a dead rel_id.
      Audit.where(rel_model: "Volume", rel_id: volume.id).update_all(rel_id: nil) if volume.persisted?
      VolumeMap.where(id: volume_map.id).delete_all if volume_map&.persisted?
      Volume.where(id: volume.id).delete_all if volume.persisted?

      failed!(reason)
    end

    # @return [Symbol] :created
    def created!
      record! "Created volume #{volume.label} (#{volume.id}) for #{service_ref} at #{volume_map.mount_path}; " \
        "containers mount it on their next rebuild", CREATED_EVENT_CODE
      :created
    end

    # @param [String] reason
    # @return [Symbol] :skipped
    def skipped!(reason)
      record! "Skipped #{service_ref}: #{reason}", SKIPPED_EVENT_CODE
      :skipped
    end

    # @param [String] reason
    # @return [Symbol] :failed
    def failed!(reason)
      record! "Failed #{service_ref}: #{reason}", FAILED_EVENT_CODE
      :failed
    end

    # Exactly one event detail line per call.
    #
    # @param [String] msg
    # @param [String] code
    # @return [nil]
    def record!(msg, code)
      @message = msg
      if event
        begin
          event.event_details.create!(data: msg, event_code: code)
        rescue
          nil
        end
      end
      nil
    end

    # @return [String]
    def service_ref
      "#{service.label} (#{service.id})"
    end
  end
end
