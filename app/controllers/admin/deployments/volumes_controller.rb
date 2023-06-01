class Admin::Deployments::VolumesController < Admin::Deployments::BaseController

  def index
    @volumes = Volume.where(deployment_id: @deployment.id).sorted
    return render(template: "admin/deployments/volumes/index", layout: false) if request.xhr?
  end

end
