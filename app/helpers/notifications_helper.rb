module NotificationsHelper

  def notifier_transport_list
    [
      ['Email', 'email'],
      ['Google Chat', 'google'],
      ['Keybase', 'keybase'],
      ['Matrix', 'matrix'],
      ['Microsoft Teams', 'msteams'],
      ['Slack', 'slack'],
      ['WebHook', 'webhook']
    ]
  end

  def notifier_rule_table_list(notifier, base_path)
    return '...' if notifier.rules.nil?
    if notifier.rules.count > 3
      "#{notifier.rules[0..2].join(', ')}, #{link_to %Q((+#{notifier.rules.count - 3} more)), "#{base_path}/#{notifier.id}/edit"}".html_safe
    else
      notifier.rules.join(', ')
    end
  end

  def admin_notifier_available_rules
    (SystemNotification.available_alerts + SystemNotification.prometheus_alerts + SystemNotification.app_event_alerts).sort
  end

  def notifier_checkbox_select_all(notifier, rules)
    available_rules = rules.nil? ? [] : rules.sort
    current_rules = notifier.rules.nil? ? [] : notifier.rules.sort
    %Q(
      <input type="checkbox" id="select_all_boxes" class="notification_select_all_rules" name="select_all_boxes" #{available_rules == current_rules ? 'checked="checked">' : '>'}
    ).html_safe
  end

end

