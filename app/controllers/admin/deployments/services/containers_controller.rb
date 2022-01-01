class Admin::Deployments::Services::ContainersController < Admin::Deployments::Services::BaseController

  def index
    @containers = @service.containers.order(:name)
    if request.xhr?
      return render(template: "admin/deployments/services/containers/index", layout: false)
    end
  end

end