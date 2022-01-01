module ContainerDomainsHelper

  def container_domain_path(domain)
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
