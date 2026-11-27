module Admin::SettingsHelper
  def setting_billing_module_list
    [%w[None none], %w[WHMCS Whmcs]]
  end

  def settings_license_header(p1, p2)
    return "panel-danger" if p2 != "Active"
    return "panel-warning" if p1
    "panel-success"
  end

  def normalize_setting_group(group)
    return "ACME Certificates" if group == "acme"
    group.split("_").map { |i| i.capitalize }.join(" ")
  rescue # quick fallback to original group name
    group
  end

  def normalize_setting_title(name)
    return "Container Registry Certificate Name" if name == "cr_le"
    return "Enable ACME" if name == "le"
    return "DNS Alias Zone" if name == "le_dns_alias_zone"
    return "DNS Provider" if name == "le_dns_provider"
    return "DNS Provider Credentials" if name == "le_dns_provider_secret"
    return "Enable Job" if name == "le_auto"
    name.split("_").map do |i|
      %w[acme id url smtp].include?(i.downcase) ? i.upcase : i.downcase.capitalize
    end.join(" ")
  rescue # quick fallback to original name
    name
  end

  def admin_setting_value(setting)
    return tag.i(nil, class: "fa-solid fa-ellipsis") if setting.value.blank?
    if setting.encrypted?
      return tag.i(nil, class: "fa-solid fa-ellipsis") if setting.decrypted_value.blank?
      return admin_provider_env_summary(setting) if setting.name == "le_dns_provider_secret"
      return "[ENCRYPTED]"
    end
    return (setting.value == "t") ? "Yes" : "No" if %w[t f].include?(setting.value)
    truncate setting.value, length: 35
  end

  # Variable count only; the values are secrets.
  def admin_provider_env_summary(setting)
    count = Setting.parse_provider_env(setting.decrypted_value).size
    "[ENCRYPTED] #{pluralize(count, "variable")}"
  rescue ArgumentError
    tag.span("Invalid", class: "label label-danger")
  end

  def setting_display_in_fw_font?(setting)
    %w[ssh_motd le_dns_provider_secret].include?(setting.name)
  end

  def setting_single_line?(setting)
    %w[le_dns_provider le_dns_alias_zone].include?(setting.name)
  end

  def setting_placeholder(setting)
    case setting.name
    when "le_dns_provider" then "e.g. cloudflare"
    when "le_dns_provider_secret" then "CLOUDFLARE_DNS_API_TOKEN=..."
    when "le_dns_alias_zone" then "e.g. acme.example.com"
    end
  end

  # Side-panel help shown on the edit page.
  def setting_help_partial(setting)
    "admin/settings/help/acme_dns" if %w[le_dns_provider le_dns_provider_secret le_dns_alias_zone].include?(setting.name)
  end

  # Problems with the load balancer certificate setup, for the ACME group.
  def acme_lb_warnings
    return [] unless LoadBalancer.where(le: true).exists?
    warnings = []
    if Setting.le_dns_provider.blank?
      warnings << "No DNS provider is set, so load balancer certificates will not be issued or renewed."
    else
      begin
        warnings << "DNS provider credentials are empty." if Setting.le_dns_provider_env.empty?
      rescue ArgumentError
        warnings << "DNS provider credentials are invalid."
      end
    end
    failing = LetsEncrypt.joins(:load_balancers).where("lets_encrypts.failure_count > 0").distinct.count
    warnings << "#{pluralize(failing, "load balancer certificate")} failed to renew on the last attempt." if failing > 0
    warnings
  end

  def settings_avail_vars(setting)
    case setting.name
    when "ssh_motd"
      %w[project_name region availability_zone]
    else
      []
    end
  end

  def settings_form_cols(setting)
    if settings_avail_vars(setting).empty? && setting_help_partial(setting).nil? && setting.errors.empty?
      return "col-lg-8 col-lg-offset-2 col-md-12"
    end
    "col-sm-8"
  end
end
