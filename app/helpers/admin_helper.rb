module AdminHelper

  def admin_user_email_link(email)
    email_split = email.split('@')
    account = email_split.first
    domain = email_split.last
    return email if %w(outlook.com gmail.com ymail.com yahoo.com hotmail.com protonmail.com icloud.com me.com hotmail.com computestacks.com).include?(domain)
    "#{account}@<a href='http://#{domain}' target='_blank'>#{domain}</a>"
  end

  # def system_alert_header(system_ok, system_warning)
  #   if !system_ok
  #     "panel panel-danger"
  #   elsif system_warning
  #     "panel panel-warning"
  #   else
  #     "panel panel-success"
  #   end
  # end

  def admin_nav_is_containers?
    return true if request.path =~ /volumes/
    return true if request.path =~ /\/admin\/containers/
    return true if request.path =~ /\/admin\/sftp/
    return true if request.path =~ /\/admin\/container_domains/
    return true if request.path =~ /\/admin\/deployments/
    return true if request.path =~ /\/admin\/volumes/
    false
  end

  def admin_nav_is_images?
    return true if request.path =~ /\/admin\/container_images/
    return true if request.path =~ /\/admin\/container_registry/
    false
  end

end
