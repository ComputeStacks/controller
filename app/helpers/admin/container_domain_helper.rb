module Admin::ContainerDomainHelper

  def admin_new_container_domain_path(deployment)
    admin_deployments_path(deployment) + "/domains/new"
  end

  def admin_container_domains_path(domain)
    "/admin/container_domains/#{domain.id}-#{domain.domain.parameterize}"
  end

  def admin_edit_container_domains_path(domain)
    "/admin/container_domains/#{domain.id}-#{domain.domain.parameterize}/edit"
  end

end
