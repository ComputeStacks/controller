module VolumeHelper
  def volume_region(volume)
    if volume.region.nil?
      return "..." if volume.nodes.empty?
      r = []
      volume.nodes.each do |i|
        next if i.region.nil?
        r << i.region.name unless r.include?(i.region.name)
      end
      r.join(", ")
    else
      volume.region.name
    end
  end

  def volume_borg_stats(volume)
    info = volume.repo_info
    size_on_disk = 0
    total_size = 0

    unless info.empty?
      if info["usage"]
        size_on_disk = (info["usage"] / BYTE_TO_GB).round(4)
      end
      if info["size"]
        total_size = (info["size"] / BYTE_TO_GB).round(4)
      end
    end
    {
      size_on_disk: size_on_disk,
      total_size: total_size
    }
  end

  def volume_borg_backup_name(backup)
    if backup[:created]
      "#{(backup[:label] == "auto") ? "Automatic" : backup[:label]} @ #{l backup[:created].in_time_zone(Time.zone)}"
    else
      "#{(backup[:label] == "auto") ? "Automatic" : backup[:label]}"
    end
  end

  def volume_path(volume)
    if request.path =~ /admin/ && current_user.is_admin?
      "/admin/volumes/#{volume.id}"
    else
      "/volumes/#{volume.id}"
    end
  end

  # @param [Volume] volume
  def volume_ha_warning(volume)
    volume.uses_clustered_storage? ? nil : tag.span("Local Volume", class: "label label-danger", title: t("volumes.high_availability.local_disabled"))
  end

  ##
  # Given a service, determine the appropriate map label.
  # @param [Volume] volume
  # @param [Deployment::ContainerService] service
  def volume_map_label(volume, service)
    return nil if volume.owner == service
    "<span class='label label-info'><i class='fa-solid fa-link'></i> #{volume.owner.label}</span>"
  end

  def volume_attached_services(volume)
    return "..." if volume.volume_maps.empty? || volume.container_services.empty?
    links = volume.container_services.map do |i|
      link_to(i.label, container_service_path(i))
    end
    links.empty? ? "..." : links.join(", ").html_safe
  end

  ##
  # Human-readable "what is this clone doing right now", from the state machine's own state.
  #
  # @param [VolumeCloneJob] job
  # @return [String]
  def volume_clone_step(job)
    t "volumes.clone_status.steps.#{job.state}",
      default: t("volumes.clone_status.restoring")
  end

  ##
  # The per-row clone status cell on a volume list. Nil when there is nothing to report, so
  # the overwhelmingly common case (no clone, or one that finished) renders an empty cell.
  #
  # Driven by the VolumeCloneJob row, not by its EventLog: a reaper can terminate the event
  # out from under a live job (Events::EventPurger#clean_event_status!), and the row is the
  # authoritative record of what actually happened.
  #
  # @param [VolumeCloneJob, nil] job
  # @return [String, nil] html
  def volume_clone_status_label(job)
    return nil if job.nil?

    if job.working?
      tag.span icon("fa-solid fa-spin", "rotate", volume_clone_step(job)),
        class: "label label-info"
    elsif job.state == VolumeCloneJob::STATE_FAILED &&
        job.finished_at.present? && job.finished_at > VolumeCloneJob::UI_FAILURE_WINDOW.ago
      label = tag.span icon("fa-solid", "triangle-exclamation", t("volumes.clone_status.failed")),
        class: "label label-danger"
      job.event_log_id ? link_to(label, volume_clone_event_path(job)) : label
    end
  end

  ##
  # Where a customer goes to read why a clone failed. The umbrella event hangs off the
  # project, so route through the project's event list rather than the volume's.
  #
  # @param [VolumeCloneJob] job
  # @return [String, nil]
  def volume_clone_event_path(job)
    return nil if job.event_log_id.nil? || job.deployment.nil?
    "/deployments/#{job.deployment.token}/events/#{job.event_log_id}"
  end

  ##
  # The volume row, its map and the real docker volume all exist, but no container has been
  # created with the bind yet — binds are baked at container-create time, so the mount only
  # appears at the service's next natural rebuild. Until then the volume is empty, invisible
  # to the application, and its backups are deliberately suppressed. Nil once it has landed,
  # so the common case renders nothing.
  #
  # @param [Volume] volume
  # @return [String, nil] html
  def volume_pending_mount_label(volume)
    return nil unless volume.awaiting_mount?

    tag.span icon("fa-regular", "clock", t("volumes.awaiting_mount.label")),
      class: "label label-warning",
      title: t("volumes.awaiting_mount.help")
  end

  ##
  # The Backups cell for a pending volume. A bare archive count of 0 reads as a failed
  # backup schedule, but the suppression is deliberate — say so instead.
  #
  # @param [Volume] volume
  # @return [String, nil] html
  def volume_pending_mount_backups_label(volume)
    return nil unless volume.awaiting_mount?

    tag.span t("volumes.awaiting_mount.backups"),
      class: "label label-default",
      title: t("volumes.awaiting_mount.backups_help")
  end

  def new_volume_action_options
    [
      %w[Create create],
      %w[Skip skip],
      %w[Mount mount],
      %w[Clone clone]
    ].sort
  end
end
