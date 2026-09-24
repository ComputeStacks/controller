module AdminHelper
  def admin_user_email_link(email)
    email_split = email.split("@")
    account = email_split.first
    domain = email_split.last
    return email if %w[outlook.com gmail.com ymail.com yahoo.com hotmail.com protonmail.com icloud.com me.com hotmail.com computestacks.com].include?(domain)
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
    return true if /volumes/.match?(request.path)
    return true if /\/admin\/containers/.match?(request.path)
    return true if /\/admin\/sftp/.match?(request.path)
    return true if /\/admin\/container_domains/.match?(request.path)
    return true if /\/admin\/deployments/.match?(request.path)
    return true if /\/admin\/volumes/.match?(request.path)
    false
  end

  def admin_nav_is_images?
    return true if /\/admin\/container_images/.match?(request.path)
    return true if /\/admin\/container_registry/.match?(request.path)
    false
  end
end
