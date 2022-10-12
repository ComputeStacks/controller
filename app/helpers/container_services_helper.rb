module ContainerServicesHelper

  def service_image_friendly_name(service)
    n = service.image_variant.friendly_name
    n.gsub("-latest","")
  end

  ##
  # Will we display an error page when viewing this service?
  #
  # @param [Deployment::ContainerService] service
  # @return [Boolean]
  def show_error_page?(service)
    service.containers.empty? && (service.created_at < 5.minutes.ago || service.event_logs.failed.exists? )
  end

  def service_show_login(service)
    return false if service.container_image.role == 'pma'
    return false if service.is_load_balancer
    return false if show_error_page?(service)
    return false if service.deployment.skip_ssh && service.ingress_rules.empty?
    true
  end

  # @param [Deployment::ContainerService] service
  def service_list_status(service)
    status = service.current_state
    msg = case status
          when 'resource_usage'
            "<span style='color:rgb(190,66,48);'>High Resource Usage</span>"
          when 'offline_containers'
            "<span style='color:rgb(217,175,95);'>Offline Containers</span>"
          when 'active_alert'
            %Q(<span style='color:rgb(217,175,95);'><i class="fa fa-exclamation-triangle fa-fw"></i> Active Alert</span>)
          else
            nil
          end

    msg = '<i class="fa fa-refresh fa-spin fa-fw"></i>' if status == 'working' && msg.nil?
    msg = '<i class="fa fa-exclamation-triangle fa-fw"></i>' if status == 'alert' && msg.nil?
    msg.nil? ? '' : "#{msg}&nbsp;&nbsp;|&nbsp;&nbsp;".html_safe
  end

  # @param [Deployment::ContainerService] service
  def service_img_icon_tag(service)
    %Q(<img src="#{image_path service.container_image.icon_url}" style="cursor:pointer;max-width:35px;height:20px;padding-right:10px;" title="#{service.name}" onclick="window.location='#{container_service_path(service)}';" alt="#{service.name}" class="img-circle" />).html_safe
  end

  # @param [Deployment::ContainerService] service
  def service_list_banner_color(service)
    case service.current_state
    when 'starting', 'stopping', 'working'
      'panel-info'
    when 'alert'
      'panel-danger'
    when 'offline_containers', 'resource_usage', 'active_alert'
      'panel-warning'
    when 'online'
      'panel-success'
    else # inactive
      'panel-default'
    end
  end

  def service_ha_label(service)
    service.can_migrate? ? tag.span(t('containers.high_availability.enabled'), class: 'label label-success') : tag.span(t('containers.high_availability.disabled'), class: 'label label-danger')
  end

  # Find all MySQL Containers for a deployment
  def service_mysql_containers(deployment)
    return [] if deployment.nil?
    deployment.services.where("container_images.role = 'mysql'").joins(:container_image)
  end

  # # Find the MySQL Password Obj for a ContainerService
  def service_mysql_password(service)
    return nil if service.nil?
    service.setting_params.find_by(name: 'mysql_password')
  end

  # What's displayed in the domain portion of the service list page for a project
  def service_list_domain(service)
    return service.containers.first&.local_ip if service.public_network?
    if service.default_domain && service.has_domain_management
      link_to truncate(service.default_domain, length: 50), "https://#{service.default_domain}", target: '_blank'
    else
      if service.public_ip.empty?
        ips = service.containers.map { |i| i.local_ip }
        truncate ips.count > 3 ? "#{ips[0..2].join(', ')}, ..." : ips.join(', '), length: 50
      else
        service.public_ip[0]
      end
    end
  end

  def service_list_status_indicator(service)
    case service.current_state
    when 'online'
      return 'Online' if service.container_image.service_container?
      link_to service_auto_scale_status(service), container_service_auto_scale_path(service)
    when 'inactive', 'offline_containers'
      %Q( #{tag.i(nil, class: 'text-warning fa fa-exclamation-triangle')} Offline Containers ).html_safe
    when 'alert', 'active_alert', 'resource_usage'
      %Q( #{tag.i(nil, class: 'text-danger fa fa-exclamation-triangle')} Alert ).html_safe
    when 'working'
      'Operation In Progress'
    else
      service.current_state
    end
  end

end
