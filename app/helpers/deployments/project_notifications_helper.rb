module Deployments
  module ProjectNotificationsHelper

    # Are there any available rules that we can add to this project?
    #
    # @param [Deployment] project
    # @return [Boolean]
    def can_add_project_notification?(project)
      project.notification_rules.count < UserNotification.available_alerts.count
    end

    # Available notifications that we can add to this project
    #
    # @param [Deployment] project
    # @param [Deployment::NotificationRule] alert
    def available_project_notifications(project, alert = nil)
      if alert.nil?
        UserNotification.available_alerts - project.notification_rules.select( Arel.sql(%Q(DISTINCT alert_name) )).pluck(:alert_name)
      else
        UserNotification.available_alerts - project.notification_rules.select( Arel.sql(%Q(DISTINCT alert_name) )).where.not(id: alert.id).pluck(:alert_name)
      end
    end


  end
end
