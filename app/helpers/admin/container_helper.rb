module Admin::ContainerHelper

  def admin_containers_path(container)
    "/admin/containers/#{container.id}"
  end

  def admin_container_start_path(container)
    "#{container.is_a?(Deployment::Sftp) ? admin_sftp_path(container) : admin_containers_path(container)}/power/start"
  end

  def admin_container_stop_path(container)
    "#{container.is_a?(Deployment::Sftp) ? admin_sftp_path(container) : admin_containers_path(container)}/power/stop"
  end

  def admin_container_restart_path(container)
    "#{container.is_a?(Deployment::Sftp) ? admin_sftp_path(container) : admin_containers_path(container)}/power/restart"
  end

  def admin_container_rebuild_path(container)
    "#{container.is_a?(Deployment::Sftp) ? admin_sftp_path(container) : admin_containers_path(container)}/power/rebuild"
  end

  def admin_sftp_path(container)
    "/admin/sftp/#{container.id}"
  end

  def admin_container_resources(container)
    if container.service&.package
      link_to_package @container.service.package
    else
      "#{container.cpu} CORE / #{container.memory} MB"
    end
  end

  ##
  # Provide feedback when a field is empty due to provisioning

  def container_name_indicator(container)
    container.name.blank? ? icon('fa-solid fa-spin', 'rotate') : container.name
  end

  def container_status_indicator(container)
    container.current_state.blank? ? icon('fa-solid fa-spin', 'rotate') : container.current_state.capitalize
  end

  def container_node_indicator(container)
    container.node.nil? ? icon('fa-solid fa-spin', 'rotate') : container.node.label
  end

  def container_ip_indicator(container)
    container.local_ip.nil? ? icon('fa-solid fa-spin', 'rotate') : container.local_ip
  end

end
