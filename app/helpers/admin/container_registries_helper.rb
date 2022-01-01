module Admin::ContainerRegistriesHelper

  def admin_registries_path
    "/admin/container_registry"
  end

  def new_admin_registry_path
    admin_registries_path + "/new"
  end

  def admin_registry_path(registry)
    admin_registries_path + "/" + registry.id.to_s
  end

  def edit_admin_registry_path(registry)
    admin_registry_path(registry) + "/edit"
  end

  def admin_registry_collaborators_path(registry)
    admin_registry_path(registry) + "/collaborators"
  end

  def admin_registry_collaborator_path(registry, collaborator)
    admin_registry_collaborators_path(registry) + "/" + collaborator.id.to_s
  end

end
