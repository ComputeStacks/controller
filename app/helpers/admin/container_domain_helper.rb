module Admin::ContainerDomainHelper

  def admin_container_domains_path(domain)
    "/admin/container_domains/#{domain.id}-#{domain.domain.parameterize}"
  end

  def admin_edit_container_domains_path(domain)
    "/admin/container_domains/#{domain.id}-#{domain.domain.parameterize}/edit"
  end

end