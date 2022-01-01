module AuditHelper

  def audit_description(audit)
    d = []
    u = nil
    u = 'me' if audit.user == current_user
    u = 'system administrator' if audit.user&.is_admin
    u = 'unknown user' if u.nil? && audit.user
    u = 'system' if u.nil?
    d << u.capitalize
    d << audit.event
    d << audit.formatted_name
    d.join(' ')
  end

  def performer(audit)
    return 'System' if audit.nil? || audit.user.nil?
    return 'Support Staff' if audit.user.is_admin && !current_user.is_admin
    return audit.user.full_name unless current_user.is_admin
    "<a href='#{admin_user_path(audit.user)}'>#{audit.user.full_name}</a>".html_safe
  end

end
