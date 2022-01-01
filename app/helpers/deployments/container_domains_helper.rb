module Deployments::ContainerDomainsHelper

  def domain_le_badge(domain)
    if domain.le_active?
      tag.span('LetsEncrypt SSL Installed', class: 'label label-success', style: 'margin-left:5px;').html_safe
    elsif domain.le_enabled && (domain.le_ready || (!domain.le_ready && domain.le_ready_checked.nil?))
      tag.span('LetsEncrypt SSL Pending', class: 'label label-default', style: 'margin-left:5px;').html_safe
    elsif domain.le_enabled && domain.le_ready_checked
      tag.span('LetsEncrypt SSL Error: Check DNS Settings', class: 'label label-danger', style: 'margin-left:5px;').html_safe
    else
      nil
    end
  end

end