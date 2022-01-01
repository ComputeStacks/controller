module Admin::AuditHelper

  def admin_audit_description(audit)
    d = []
    d << audit.formatted_user
    d << audit.event
    d << audit.formatted_name
    d.join(' ')
  end

  def audit_obj_url(audit)
    return nil if audit.linked.nil?
    return "/admin/regions/#{audit.linked.id}" if audit.linked.is_a?(Node)
    audit.linked.url_path(current_user)
  rescue
    nil
  end

end
