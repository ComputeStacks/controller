module Admin::ContainerServicesHelper

  def admin_container_service_path(service)
    admin_deployments_path(service.deployment) + "/services/#{service.id}"
  end

end
