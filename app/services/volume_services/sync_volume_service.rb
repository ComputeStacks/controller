module VolumeServices
  ##
  # Sync volumes
  #
  # This will only look for locally-created volumes, like those
  # automatically created when a user forgets to define a `VOLUME` in
  # ComputeStacks.
  #
  # This will do two things:
  # * Disables backups on that volume
  # * Pins the container to this node (when using clustered storage)
  #
  # @!attribute event
  #   @return [EventLog]
  class SyncVolumeService
    attr_accessor :event,
      :skipped_volumes,
      :unimportable_volumes,
      :failed_volumes

    # @param [EventLog] event
    def initialize(event)
      self.event = event
      self.skipped_volumes = {}      # no container of ours mounts it
      self.unimportable_volumes = {} # we know whose it is, but it cannot be a mount (stable)
      self.failed_volumes = {}       # a genuine fault: exception or DB error
    end

    # @return [Boolean]
    def perform
      Node.online.each do |node|
        begin
          # Returns an array of Docker::Volume
          available_volumes = DockerVolumeLocal::Node.new(node).list_all_volumes
        rescue => e # Allow us to gracefully fail for an offline node
          ExceptionAlertService.new(e, "9c158106939a83f9").perform
          next
        end

        # Need to list out all containers and their attached volumes in
        # order to figure out where these volumes are mounted.

        available_volumes.each do |vol|
          if vol.info.dig("Labels", "com.computestacks.role")
            next if %w[backup system].include? vol.info["Labels"]["com.computestacks.role"]
            next if vol.info["Name"] == "consul-data"
          end

          ##
          # For existing volumes, we just want to note that it exists on this node.
          existing_volume = Volume.find_by(name: vol.info["Name"])
          if existing_volume
            unless existing_volume.nodes.include?(node)
              existing_volume.nodes << node
              event.event_details.create!(
                data: "Found volume #{vol.info["Name"]} on a new node: #{node.label}; updating...",
                event_code: "8e101399a65eabb8"
              )
            end
            next
          end

          # Nothing about one volume may end the sweep. This rescue is the structural guarantee,
          # not the narrower ones inside `import_volume`: a malformed docker mount entry reaches
          # `Volumes::VolumeMount#modify_mount_point`, and the desired-state PUT after the import
          # only tolerates the transport errors listed in `Agent::Client#with_transport_rescue`
          # (an EHOSTUNREACH or an SSL error escapes it). Either used to unwind past #perform
          # into SyncLocalVolumeWorker's catch-all, which alerts but never closes the EventLog —
          # leaving the run "running" forever and every later volume and node unprocessed.
          begin
            import_volume(vol, node)
          rescue => e
            record_failure!(vol, node, "#{e.class}: #{e.message}")
          end
        end
      end
      unless skipped_volumes.empty?
        event.event_details.create!(
          data: "Found the following volumes, but skipped due to missing local service:\n\n#{skipped_volumes.to_yaml}",
          event_code: "ad0490ed8c707384"
        )
      end

      # Volumes we understand but cannot represent. Reported, never failed: these are stable
      # conditions (the service already maps that path, or the path is nested under an existing
      # mount) and failing the nightly run for them would mean an event marked failed every
      # night until the affected service happens to be rebuilt.
      unless unimportable_volumes.empty?
        event.event_details.create!(
          data: "Found the following volumes, but they cannot be represented as a mount:\n\n#{unimportable_volumes.to_yaml}",
          event_code: "ad0490ed8c707384"
        )
      end

      # Genuine faults — an exception, or a database error on write. Collected and reported after
      # the whole fleet has been swept rather than aborting on the first one. Each already has
      # its own detail line, so this only raises the operator-facing signal and the run status.
      unless failed_volumes.empty?
        count = failed_volumes.values.flatten.count
        SystemEvent.create!(
          message: "Volume sync failed to import #{count} volume(s)",
          log_level: "warn",
          data: {volumes: failed_volumes, event: event.id},
          event_code: "23d980fd2ed94884"
        )
        event.fail! "Failed to import #{count} volume(s)"
      end

      return false if event.failed?
      event.done!
      true
    end

    private

    # @param [Docker::Volume] vol
    # @param [Node] node
    def import_volume(vol, node)
      ##
      # Identify existing services
      existing_container_service = nil
      service_mount_path = nil

      volume_inspect = Volume.inspect_volume_by_name vol.info["Name"]
      volume_inspect.each do |i|
        next if i[:container_name].blank?
        c = Deployment::Container.find_by(name: i[:container_name])
        next if c.nil?
        existing_container_service = c.service
        service_mount_path = i[:mount_path]
      end

      if existing_container_service.nil? # Skip it!
        (skipped_volumes[node.label] ||= []) << vol.info["Name"]
        return
      end

      # `VolumeMap before_validation :modify_mount_point` rewrites the path through
      # `Volumes::VolumeMount.safe_mount` (Zaru), so a docker Destination containing anything it
      # sanitises would be STORED under a different path than the one the container actually
      # uses. Importing that would map a path corresponding to nothing: the bind at the next
      # rebuild would land somewhere the app never writes, and docker would mint yet another
      # anonymous volume at the real path. Refuse instead of storing a lie. Also covers a mount
      # entry with no Destination at all, which would otherwise reach `safe_mount(nil)`.
      if service_mount_path.blank?
        return record_unimportable!(vol, node, "docker reported no mount path")
      end
      normalized = VolumeMap.safe_mount(service_mount_path)
      if normalized != service_mount_path
        return record_unimportable!(
          vol, node,
          "docker reports #{service_mount_path.inspect}, which would be stored as #{normalized.inspect}"
        )
      end

      new_volume = existing_container_service.volumes.new(
        label: vol.info["Name"],
        name: vol.info["Name"],
        deployment: existing_container_service.deployment,
        user: existing_container_service.deployment.user,
        borg_enabled: false,
        enable_sftp: false,
        region: existing_container_service.region,
        volume_backend: "local" # TODO: Read the drive from the docker api.
      )
      new_volume.nodes << node

      # The owner map. Without it the imported volume has no `container_service` at all
      # (Volume#container_service resolves through `volume_maps.primary.first`), so it is
      # service-less: `after_commit :set_detached` stamps `detached_at`, which makes
      # BillingUsageServices::CollectUsageService#offline_storage mint a standalone "Detached
      # Volume" subscription and then accrue a usage row for it on every collection cycle,
      # forever. That is the state 19 volumes are in on production.
      #
      # This create used to sit inside the `unless new_volume.save` branch below — it ran ONLY
      # when the volume had failed to save, where all it could do was raise. So in practice
      # every successful import produced a map-less volume, and the failure branch was close to
      # unreachable (`save` returning false needs a blank label/name or a name collision, and
      # `Volume.find_by(name:)` above has already excluded the collision).
      volume_map = existing_container_service.volume_maps.new(
        volume: new_volume,
        mount_path: service_mount_path,
        mount_ro: false,
        is_owner: true
      )

      # Validate both before writing either, so a rejected import leaves no orphan Volume row.
      #
      # A rejection here is a SKIP, not a failure, and the distinction matters: the common cause
      # is that the service already maps this path — which is exactly what the image volume
      # cascade produces, since it attaches a volume at (say) /tmp and deliberately rebuilds
      # nothing, leaving docker's anonymous volume mounted there until the container is next
      # rebuilt. Treating that as a failure would mark this job failed every night, indefinitely,
      # for a condition VolumeServices::AttachTemplateVolumeService itself calls a benign skip.
      # Nesting under an existing mount (VolumeMap#no_nested_volumes) is equally stable.
      unless new_volume.valid? && volume_map.valid?
        errors = (new_volume.errors.full_messages + volume_map.errors.full_messages).uniq
        return record_unimportable!(vol, node, errors.join(" "))
      end

      # One transaction, so `set_detached` sees the map on commit and leaves `detached_at` nil.
      begin
        ActiveRecord::Base.transaction do
          new_volume.save!
          volume_map.save!
        end
      rescue ActiveRecord::ActiveRecordError => e
        return record_failure!(vol, node, "#{e.class}: #{e.message}")
      end

      event.event_details.create!(
        data: "Imported volume: #{new_volume.name} for service #{existing_container_service.label} (#{existing_container_service.id}).\n\nMounted at: #{service_mount_path}",
        event_code: "b996ebd83c79b1cd"
      )
      # No explicit `update_consul!` here: `Volume after_commit :update_consul!, on: [:create,
      # :update]` has already pushed this volume's desired-state, and calling it again only sends
      # a second identical PUT.
      nil
    end

    # A volume we can attribute to a service but cannot represent as a mount. Stable condition,
    # so it is reported and the run still completes — see the rationale at the validation site.
    #
    # @param [Docker::Volume] vol
    # @param [Node] node
    # @param [String] reason
    # @return [nil]
    def record_unimportable!(vol, node, reason)
      (unimportable_volumes[node.label] ||= []) << "#{vol.info["Name"]}: #{reason}"
      nil
    end

    # A genuine fault: an exception, or a database error while writing. Keeps sweeping; #perform
    # raises the SystemEvent and fails the event once the run is finished.
    #
    # @param [Docker::Volume] vol
    # @param [Node] node
    # @param [String] reason
    # @return [nil]
    def record_failure!(vol, node, reason)
      (failed_volumes[node.label] ||= []) << "#{vol.info["Name"]}: #{reason}"
      event.event_details.create!(
        data: "Failed to import volume #{vol.info["Name"]} on #{node.label}.\n\n#{reason}",
        event_code: "23d980fd2ed94884"
      )
      nil
    end
  end
end
