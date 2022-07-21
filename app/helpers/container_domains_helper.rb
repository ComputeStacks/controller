module ContainerDomainsHelper

  def new_container_domain_path(deployment)
    return admin_new_container_domain_path(deployment) if current_user.is_admin && deployment.user != current_user
    "/container_domains/new?deployment_id=#{deployment.token}"
  end

  def container_domain_path(domain)
    return admin_container_domains_path(domain) if current_user.is_admin && domain.user != current_user
    "/container_domains/#{domain.id}-#{domain.domain.parameterize}"
  end

  def edit_container_domain_path(domain)
    container_domain_path(domain) + "/edit"
  end

  # Available projects for a given domain
  def container_domain_project_list(domain)
    if request.path =~ /admin/ && current_user.is_admin
      domain.user ? domain.user.deployments.sorted : []
    else
      Deployment.find_all_for(current_user)
    end
  end

end
