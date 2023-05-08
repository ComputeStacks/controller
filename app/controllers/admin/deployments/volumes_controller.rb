class Admin::Deployments::VolumesController < Admin::Deployments::BaseController

  def index
    @volumes = @deployment.volumes.sorted
    return render(template: "admin/deployments/volumes/index", layout: false) if request.xhr?
  end

end
