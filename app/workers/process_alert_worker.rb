# ProcessAlertWorker will perform tasks based on the alert
#
# Tasks expected to be performed
# * Notifications via the requested delivery method
# * AutoScale events
# * Status Updates
#
class ProcessAlertWorker
  include Sidekiq::Worker

  def perform(alert_id)
    event = nil
    alert = AlertNotification.find_by(id: alert_id)
    return if alert.nil?

    if alert.active? && alert.has_notifications?
      ##
      # Process Notifications

      event = EventLog.create!(
        locale: 'alert.notifications.processing',
        locale_keys: { name: alert.name },
        event_code: 'dfa883c97eb7875e',
        status: 'running'
      )
      event.alert_notifications << alert
      event.containers << alert.container if alert.container
      event.sftp_containers << alert.sftp_container if alert.sftp_container

      deployment = if alert.container
                     alert.container.deployment
                   elsif alert.sftp_container
                     alert.sftp_container.deployment
                   else
                     nil
                   end

      if deployment

        deployment.project_notifiers.where( Arel.sql %Q('#{alert.name}' = ANY (rules)) ).each do |i|
          i.current_event = event
          i.fire_alert! alert
        end

        deployment.user.user_notifications.where( Arel.sql %Q('#{alert.name}' = ANY (rules)) ).each do |i|
          i.current_event = event
          i.fire_alert! alert
        end

      end

      SystemNotification.where( Arel.sql %Q('#{alert.name}' = ANY (rules)) ).each do |i|
        i.current_event = event
        i.fire_alert! alert
      end

    end

    ##
    # State Management

    # Node is offline
    if alert.name == 'NodeUp' && alert.node
      NodeWorkers::HeartbeatWorker.perform_async alert.node.to_global_id.to_s
    end

    # Container has gone away
    if alert.name == 'ContainerKilled' && alert.active?
      if alert.container
        ContainerWorkers::RecoverContainerWorker.perform_async alert.container.to_global_id.to_s, alert.to_global_id.to_s
      end
      if alert.sftp_container
        ContainerWorkers::RecoverContainerWorker.perform_async alert.sftp_container.to_global_id.to_s, alert.to_global_id.to_s
      end
    end

    ##
    # AutoScale

    if alert.active? && (alert.container && alert.container.service.auto_scale)

      if %w(ContainerCpuUsage ContainerMemoryUsage).include? alert.name
        container_service = alert.container.service
        # Any alert, created within 5 minutes, should halt auto-scaling.
        alert_triggered = container_service.alert_notifications.where(
                              Arel.sql( %Q( alert_notifications.name = '#{alert.name}' AND alert_notifications.created_at > '#{5.minutes.ago.iso8601}' ) )
                            ).exists?
        # Determine if we've had an alert like this in the past 5 minutes.
        unless alert_triggered
          resource_kind = alert.name == 'ContainerCpuUsage' ? 'cpu' : 'memory'
          ContainerServiceWorkers::AutoScaleServiceWorker.perform_async container_service.to_global_id.to_s, resource_kind
        end
      end

    end

  ensure
    event&.done! if event&.running?
  end

end
