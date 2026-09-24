class Admin::Deployments::Services::ContainersController < Admin::Deployments::Services::BaseController
  def index
    @containers = @service.containers.order(:name)
    if request.xhr?
      render(template: "admin/deployments/services/containers/index", layout: false)
    end
  end
end
