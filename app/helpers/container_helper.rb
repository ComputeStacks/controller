module ContainerHelper

  # @param [Deployment::Container] container
  # @return [String]
  def container_start_path(container)
    %Q(#{container_path(container)}/power_management/start)
  end

  # @param [Deployment::Container] container
  # @return [String]
  def container_stop_path(container)
    %Q(#{container_path(container)}/power_management/stop)
  end

  # @param [Deployment::Container] container
  # @return [String]
  def container_restart_path(container)
    %Q(#{container_path(container)}/power_management/restart)
  end

  # @param [Deployment::Container] container
  # @return [String]
  def container_rebuild_path(container)
    %Q(#{container_path(container)}/power_management/rebuild)
  end

  # @param [Deployment::Container] container
  # @return [String]
  def container_stats(container)
    return '...' if container.status.blank? || container.status == 'stopped'
    c = container.stats
    "#{c[:cpu]}% / #{c[:mem]}%"
  rescue
    '...'
  end

  def container_table_list_class(container)
    container.alert_notifications.active.exists? ? "danger" : ""
  end

  def container_current_disk_usage(container)
    return '...' if container.status.blank? || container.status == 'stopped'
    u = container.metric_current_disk_usage
    u.nil? ? '...' : ('%.5f' % u + " GB")
  rescue
    '...'
  end

end
