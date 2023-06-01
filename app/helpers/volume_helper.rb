module VolumeHelper

  def volume_region(volume)
    if volume.region.nil?
      return '...' if volume.nodes.empty?
      r = []
      volume.nodes.each do |i|
        next if i.region.nil?
        r << i.region.name unless r.include?(i.region.name)
      end
      r.join(', ')
    else
      volume.region.name
    end
  end

  def volume_borg_stats(volume)
    info = volume.repo_info
    size_on_disk = 0
    total_size = 0

    unless info.empty?
      if info['usage']
        size_on_disk = (info['usage'] / BYTE_TO_GB).round(4)
      end
      if info['size']
        total_size = (info['size'] / BYTE_TO_GB).round(4)
      end
    end
    {
      size_on_disk: size_on_disk,
      total_size: total_size
    }
  end

  def volume_borg_backup_name(backup)
    if backup[:created]
      "#{backup[:label] == 'auto' ? 'Automatic' : backup[:label]} @ #{l backup[:created].in_time_zone(Time.zone)}"
    else
      "#{backup[:label] == 'auto' ? 'Automatic' : backup[:label]}"
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
    volume.uses_clustered_storage? ? nil : tag.span("Local Volume", class: "label label-danger", title: t('volumes.high_availability.local_disabled'))
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
    return '...' if volume.volume_maps.empty? || volume.container_services.empty?
    links = volume.container_services.map do |i|
      link_to(i.label, container_service_path(i))
    end
    links.empty? ? '...' : links.join(', ').html_safe
  end

  def new_volume_action_options
    [
      %w(Create create),
      %w(Skip skip),
      %w(Mount mount),
      %w(Clone clone),
    ].sort
  end

end
