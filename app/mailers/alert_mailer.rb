class AlertMailer < ApplicationMailer

  layout false

  # @param [AlertNotification] alert
  # @param [Deployment::NotificationRule::Email] email_alert (Can also be SystemNotification::Email)
  def alert_notification(alert, email_alert)
    @header = "Alert: #{alert.name}"
    @body = alert.description
    @labels = alert.labels.is_a?(Array) ? alert.labels : [] # [ [k,v] ]
    if alert.container
      c = alert.container
      s = c.service
      @labels << [ "Project", c.deployment&.name ]
      @labels << [ "Container", c.name ]
      @labels << [ "Service", s.label ]
      @labels << [ "Primary Domain", s.master_domain.domain ] if s.master_domain
    end
    @labels << [ "SFTP Container", alert.sftp_container.name ] if alert.sftp_container
    @labels << [ "Node", alert.node.label ] if alert.node

    mail to: email_alert, subject: "[#{Setting.app_name}] #{alert.name}"
  end

  # @param [string] subject
  # @param [string] description
  # @param [SystemNotification::Email] email_alert
  def app_event_notification(subject, description, email_alert, labels = [])
    @header = subject
    @body = description
    @labels = labels
    mail to: email_alert, subject: "[#{Setting.app_name}] #{subject}"
  end

end
