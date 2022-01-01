module Notifications
  module Common
    extend ActiveSupport::Concern

    included do

      scope :sorted, -> { order "label, notifier" }

      validates :label, presence: true
      validates :notifier, presence: true
      validates :value, presence: true
      validate :ensure_has_rules

    end

    class_methods do
      ##
      # Available alerts to choose from:
      #
      # Prometheus Alerts:
      # * ContainerCpuUsage
      # * ContainerMemoryUsage
      #
      # App Event Notifications:
      # * ContainerBootFailed
      # * ContainerCreated
      # * ContainerDestroyed
      #
      def available_alerts
        %w(
          ContainerCpuUsage
          ContainerMemoryUsage
          ContainerBootFailed
          ContainerCreated
          ContainerDestroyed
        )
      end
    end

    def fire_alert!(alert)
      n = notifier_resource
      n.alert = alert
      n.event = current_event if current_event
      n.perform
    end

    def fire_app_alert!(obj, alert_name)
      n = notifier_resource
      n.subject = obj.app_event_subject(alert_name)
      n.description = obj.app_event_description(alert_name)
      n.labels = obj.app_event_labels
      n.perform
    end

    # Trigger App Alert with supplied data
    #
    # When triggering a notification for an object being destroyed,
    # we need to pass the full value since it most likely will be unavilable
    # by the time the worker can process this.
    #
    # @return [Boolean]
    def fire_app_alert_with_data!(subject, description, labels = [])
      n = notifier_resource
      n.subject = subject
      n.description = description
      n.labels = labels
      n.perform
    end

    def notifier_formatted_value
      case notifier
      when 'slack'
        value.blank? ? '...' : value.gsub("https://hooks.slack.com/services/", "")
      when 'google'
        value.blank? ? '...' : value.gsub("https://chat.googleapis.com/v1/spaces/", "").split("/")[0]
      when 'matrix'
        value.blank? ? '...' : value.split("/appservice-webhooks/api/v1/matrix/hook/")[0]
      else
        value
      end
    end

    def notifier_name
      case notifier
      when 'google'
        'Google Chat'
      when 'msteams'
        'Microsoft Teams'
      else # email, slack, webhook
        notifier.capitalize
      end
    end

    private

    def ensure_has_rules
      if rules.nil? || rules.empty?
        errors.add(:rules, 'must not be empty')
      end
    end

    def notifier_resource
      case notifier
      when 'email'
        NotifierServices::EmailNotifier.new(value)
      when 'keybase'
        NotifierServices::KeybaseNotifier.new(value)
      when 'matrix'
        NotifierServices::MatrixNotifier.new(value)
      when 'slack'
        NotifierServices::SlackNotifier.new(value)
      else # webhook, google, msteams
        NotifierServices::WebhookNotifier.new(value)
      end
    end

  end
end
