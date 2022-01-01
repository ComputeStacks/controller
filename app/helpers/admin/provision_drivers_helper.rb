module Admin::ProvisionDriversHelper

  def pd_module_name(modname)
    case modname.downcase
    when 'pdns'
      'PowerDNS'
    else
      modname
    end
  end

end