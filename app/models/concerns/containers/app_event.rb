module Containers
  module AppEvent
    extend ActiveSupport::Concern

    included do

      after_create_commit :trigger_create_notifier
      before_destroy :trigger_destroy_notifier, prepend: true

    end

    def app_event_subject(alert_name)
      case alert_name
      when 'ContainerCreated'
        "Container Created"
      when 'ContainerDestroyed'
        "Container Destroyed"
      when 'ContainerBootFailed'
        "Container Boot Failure"
      else
        ""
      end
    end

    def app_event_description(alert_name)
      base_desc = "#{name} (#{service.label})"
      case alert_name
      when 'ContainerCreated'
        "#{base_desc} has been created"
      when 'ContainerDestroyed'
        "#{base_desc} has been destroyed."
      when 'ContainerBootFailed'
        "#{base_desc} automatic recovery has failed."
      else
        ""
      end
    end

    def app_event_labels
      [
        { 'key' => 'link', 'value' => %Q(#{PORTAL_HTTP_SCHEME}://#{Setting.hostname}/containers/#{id}) },
        { 'key' => 'Name', 'value' => name },
        { 'key' => 'Service', 'value' => service.label },
        { 'key' => 'Image', 'value' => container_image.label }
      ]
    end

    private

    def trigger_create_notifier
      ProcessAppEventWorker.perform_async 'ContainerCreated', user.global_id, global_id
    end

    def trigger_destroy_notifier
      data = {
        'subject' => app_event_subject('ContainerDestroyed'),
        'description' => app_event_description('ContainerDestroyed'),
        'labels' => []
      }
      ProcessAppEventWorker.perform_async('ContainerDestroyed', user.global_id, nil, data) if user
    end

  end
end
