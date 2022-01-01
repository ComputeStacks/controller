class Deployments::VolumesController < Deployments::BaseController

  def index
    @volumes = @deployment.volumes.sorted
    if params[:js]
      render template: "deployments/volumes/index", layout: false
    end
  end

end