module Deployments::ContainerDomainsHelper
  def domain_le_badge(domain)
    if domain.le_active?
      tag.span("Automatic SSL Installed", class: "label label-success", style: "margin-left:5px;").html_safe
    elsif domain.le_enabled && (domain.le_ready || (!domain.le_ready && domain.le_ready_checked.nil?))
      tag.span("Automatic SSL Pending", class: "label label-default", style: "margin-left:5px;").html_safe
    elsif domain.le_enabled && domain.le_ready_checked
      tag.span("Automatic SSL Error: Check DNS Settings", class: "label label-danger", style: "margin-left:5px;").html_safe
    end
  end
end
