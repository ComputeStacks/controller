module Admin::SettingsHelper


  def setting_billing_module_list
    [ %w(None none), %w(WHMCS Whmcs) ]
  end


  def settings_license_header(p1, p2)
    return "panel-danger" if p2 != "Active"
    return "panel-warning" if p1
    "panel-success"
  end

  def normalize_setting_group(group)
    group.split('_').map { |i| i.capitalize }.join(' ')
  rescue # quick fallback to original group name
    group
  end

  def normalize_setting_title(name)
    return 'Container Registry Certificate Name' if name == 'cr_le'
    return 'Enable LetsEncrypt' if name == 'le'
    return 'LetsEncrypt Validation Server' if name == 'le_validation_server'
    return '1 Certificate per Domain' if name == 'le_single_domain'
    name.split('_').map do |i|
      %w(id url smtp).include?(i.downcase) ? i.upcase : i.downcase.capitalize
    end.join(' ')
  rescue # quick fallback to original name
    name
  end

  def admin_setting_value(setting)
    return tag.i(nil, class: 'fa fa-ellipsis-h') if setting.value.blank?
    if setting.encrypted?
      return setting.decrypted_value.blank? ? tag.i(nil, class: 'fa fa-ellipsis-h') : '[ENCRYPTED]'
    end
    return setting.value == 't' ? 'Yes' : 'No' if %w(t f).include?(setting.value)
    truncate setting.value, length: 35
  end

  def setting_display_in_fw_font?(setting)
    setting.name == "ssh_motd"
  end

  def settings_avail_vars(setting)
    case setting.name
    when "ssh_motd"
      %w(project_name region availability_zone)
    else
      []
    end
  end

  def settings_form_cols(setting)
    if settings_avail_vars(setting).empty? && setting.errors.empty?
      return 'col-lg-8 col-lg-offset-2 col-md-12'
    end
    'col-sm-8'
  end

end
