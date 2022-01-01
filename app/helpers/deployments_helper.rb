module DeploymentsHelper

  def deployments_path(deployment)
    "/deployments/#{deployment.token}"
  end

  def deployment_last_event(deployment)
    e = deployment.event_logs.order(updated_at: :desc).limit(1).first
    e.nil? ? t('common.never') : distance_of_time_in_words_to_now(e.created_at.in_time_zone(Time.zone), include_seconds: true)
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
      raw("<span class='label label-info'>#{I18n.t('events.status.running')} <img src='/loader.gif' style='height:12px;padding-bottom:1px;vertical-align:middle;padding-left:5px;'' /></span>")
    when "failed"
      raw("<span class='label label-danger'>#{I18n.t('events.status.failed')}</span>")
    when "info"
      raw("<span class='label label-info'><i class='fa fa-info-circle'></i> #{I18n.t('events.kind.info')}</span>")
    when "notice"
      raw("<span class='label label-info'><i class='fa fa-exclamation-circle'></i> #{I18n.t('events.kind.notice')}</span>")
    when "warning"
      raw("<span class='label label-warning'><i class='fa fa-warning'></i> #{I18n.t('events.kind.warn')}</span>")
    when "alert"
      raw("<span class='label label-danger'><i class='fa fa-warning'></i> #{I18n.t('events.kind.alert')}</span>")
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
    when 'alert'
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
        badges << tag(:i, class: 'fa fa-user-plus fa-fw', title: pluralize(deployment.deployment_collaborators.active.count, 'Collaborator'))
      end
    else
      badges << tag(:i, class: 'fa fa-users fa-fw', title: deployment.user.full_name)
    end

    if %w(working deleting).include?(status)
      badges << tag(:i, class: 'fa fa-refresh fa-spin fa-fw', title: status)
    elsif status != 'ok'
      badges << tag(:i, class: 'fa fa-fw fa-exclamation-triangle', title: 'Alert')
    else
      badges << tag(:i, class: 'fa fa-check-circle fa-fw', title: 'OK')
    end
    badges
  end

  def container_power_toggle_icon(container, class_only = true)
    status = container.status
    if status.nil? && container.created_at > 3.minutes.ago
      return "Working <i class='fa fa-refresh fa-spin fa-fw'></i>"
    elsif status.nil?
      "#{t('containers.state.unknown')} <i class='fa fa-question'></i>"
    elsif status == 'error' && container.created_at > 3.minutes.ago
      return "Working <i class='fa fa-refresh fa-spin fa-fw'></i>"
    end
    klass = case status
            when 'running', 'deployed'
              'fa-toggle-on'
            when 'stopped'
              'fa-toggle-off'
            when 'error'
              'fa-exclamation-triangle'
            when 'pending'
              'fa-clock-o'
            when 'working', 'deploying', 'building', 'deleting', 'rebuilding'
              'fa-refresh fa-spin fa-fw'
            else
              'fa-question'
            end
    return klass if class_only
    return "..." if status.nil?
    "#{status.capitalize} <i class='fa #{klass}'></i>"
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
