module NodeHelper

  def node_uptime_in_words(node)
    node.last_boot_time.nil? ? '...' : distance_of_time_in_words_to_now(node.last_boot_time)
  rescue
    '...'
  end

  def node_status_header(node)
    return 'panel-default' if node.nil? || !node.active
    if node.disconnected
      'panel-danger'
    elsif node.maintenance || node.failed_health_checks > 0
      'panel-warning'
    else
      'panel-success'
    end
  end

  def node_current_state(node)
    if node.disconnected
      'Offline'
    elsif node.maintenance
      node.job_status == 'evacuating' ? 'Entering Maintenance Mode' : 'In Maintenance Mode'
    elsif node.failed_health_checks > 0
      pluralize node.failed_health_checks, 'failed health check', plural: 'failed health checks'
    else
      return 'Online' if node.job_status == 'idle'
      node.job_status == 'checkup' ? 'Performing Checkup' : node.job_status.capitalize
    end
  end

  def node_last_event(node)
    e = node.event_logs.order(updated_at: :desc).limit(1).first
    e.nil? ? t('common.never') : distance_of_time_in_words_to_now(e.created_at.in_time_zone(Time.zone), include_seconds: true)
  end

end
