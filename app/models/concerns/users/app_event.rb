module Users
  module AppEvent
    extend ActiveSupport::Concern

    included do
      after_create_commit :trigger_create_notifier
      before_destroy :trigger_destroy_notifier, prepend: true
    end

    def app_event_subject(alert_name)
      case alert_name
      when 'UserActivated'
        "User Unsuspended"
      when 'UserCreated'
        "User Created"
      when 'UserDeleted'
        "User Deleted"
      when 'UserSuspended'
        "User Suspended"
      else
        ""
      end
    end

    def app_event_description(alert_name)
      base_desc = "#{full_name} (#{email})"
      case alert_name
      when 'UserActivated'
        "#{base_desc} has been unsuspended"
      when 'UserCreated'
        "#{base_desc} has been created."
      when 'UserDeleted'
        "#{base_desc} has been deleted"
      when 'UserSuspended'
        "#{base_desc} has been suspended"
      else
        ""
      end
    end

    def app_event_labels
      [ { 'key' => 'link', 'value' => %Q(#{PORTAL_HTTP_SCHEME}://#{Setting.hostname}/admin/users/#{id}) } ]
    end

    private

    def trigger_create_notifier
      ProcessAppEventWorker.perform_async 'UserCreated', nil, global_id
    end

    def trigger_destroy_notifier
      data = {
        'subject' => app_event_subject('UserDeleted'),
        'description' => app_event_description('UserDeleted')
      }
      ProcessAppEventWorker.perform_async 'UserDeleted', nil, nil, data
    end

  end
end
