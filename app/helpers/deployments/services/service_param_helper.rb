module Deployments::Services::ServiceParamHelper

  def service_param_path(setting)
    return nil if setting.container_service.nil?
    "/container_services/#{setting.container_service.id}/settings/#{setting.id}"
  end

end
