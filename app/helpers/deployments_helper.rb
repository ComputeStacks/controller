module DeploymentsHelper

  def deployments_path(deployment)
    "/deployments/#{deployment.token}"
  end

  def deployment_last_event(deployment)
    if deployment.event_logs.running.count.zero?
      e = deployment.last_event
      e.nil? ? t('common.never') : distance_of_time_in_words_to_now(e.in_time_zone(Time.zone), include_seconds: true)
    else
      "#{pluralize(deployment.event_logs.running.count, 'active event', 'active events')}"
    end
  end

  def deployment_icons(deployment)
    ar = []
    deployment.image_icons.each do |i|
      ar << i
    end
    ar.count > 8 ? ar[0..7] : ar
  end

  def container_service_package(service)
    if service.package
      service.package.product.label
    else
      I18n.t('billing.metered')
    end
  end

  def format_event_log(event)
    case event
    when "completed"
      raw("<span class='label label-success'>#{I18n.t('events.status.completed')}</span>")
    when "working", "running"
      raw("<span class='label label-info'>#{icon('fa-solid fa-spin', 'rotate')} #{I18n.t('events.status.running')}</div>")
    when "failed"
      raw("<span class='label label-danger'>#{I18n.t('events.status.failed')}</span>")
    when "info"
      raw("<span class='label label-info'>#{icon('fa-solid', 'circle-info')} #{I18n.t('events.kind.info')}</span>")
    when "notice"
      raw("<span class='label label-info'>#{icon('fa-solid', 'triangle-exclamation')} #{I18n.t('events.kind.notice')}</span>")
    when "warning"
      raw("<span class='label label-warning'>#{icon('fa-solid', 'circle-exclamation')} #{I18n.t('events.kind.warn')}</span>")
    when "alert"
      raw("<span class='label label-danger'>#{icon('fa-solid', 'circle-exclamation')} #{I18n.t('events.kind.alert')}</span>")
    else
      raw("<span class='label label-default'>#{event.capitalize}</span>")
    end
  end

  # @param [Deployment::EventLog] event
  def deployment_event(event)
    data = event.description
    event.containers.each do |i|
      next if i.deployment.nil?

      data = data.gsub("#{i.name}", "<a href='/containers/#{i.id}'>#{i.name}</a>")
    end
    event.container_services.each do |i|
      next if i.deployment.nil?

      data = data.gsub("[#{i.label}]", "[<a href='/container_services/#{i.id}'>#{i.label}</a>]")
    end
    data
  end

  # @param [Deployment] deployment
  def deployment_panel_header(deployment)
    case deployment.current_state
    when 'working'
      'panel-info'
    when 'ok'
      'panel-success'
    when 'warning'
      'panel-warning'
    when 'alert', 'unhealthy'
      'panel-danger'
    else # deleting
      'panel-default'
    end
  end

  # @param [Deployment] deployment
  def deployment_list_header_icon(deployment)
    badges = []
    status = deployment.current_state

    # Collaborations
    if deployment.is_resource_owner?(current_user)
      if deployment.deployment_collaborators.active.exists?
        badges << icon('fa-solid', 'user-plus', nil, { title: pluralize(deployment.deployment_collaborators.active.count, 'Collaborator') })
      end
    else
      badges << icon('fa-solid', 'users', nil, { title: deployment.user.full_name })
    end

    case status
    when 'working','deleting'
      badges << icon('fa-solid fa-spin', 'rotate', nil, { title: status })
    when 'ok'
      badges << icon('fa-solid', 'circle-check', nil, { title: 'OK' })
    when 'unhealthy'
      badges << icon('fa-solid', 'triangle-exclamation', nil, { title: 'Degraded' })
    else
      badges << icon('fa-solid', 'triangle-exclamation', nil, { title: 'Alert' })
    end
    badges
  end

  def deployment_status(deployment)
    case deployment.current_state
    when 'working'
      I18n.t('deployments.state.working')
    when 'alert'
      I18n.t('containers.health.error')
    when 'ok'
      I18n.t('deployments.state.deployed')
    when 'deleting'
      I18n.t('containers.state.deleting')
    when 'unhealthy'
      'Degraded'
    else
      "..."
    end
  end

  # Format run rate into an estimated monthly price
  #
  # @param [Deployment] deployment
  def deployment_run_rate(deployment)
    rate = deployment.run_rate
    format_currency(rate) + " /" + I18n.t('billing.month')
  end

  # @param [Deployment] deployment
  def deployment_ha_label(deployment)
    deployment.can_migrate? ? tag.span(t('containers.high_availability.enabled'), class: 'label label-success') : tag.span(t('containers.high_availability.disabled'), class: 'label label-danger')
  end

end
