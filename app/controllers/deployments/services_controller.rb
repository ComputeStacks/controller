class Deployments::ServicesController < Deployments::BaseController

  def index
    @services = if params[:web_only]
                  @deployment.services.web_only.sorted
                elsif params[:load_balancers]
                  @deployment.services.where(is_load_balancer: true).joins(:container_image).order( Arel.sql("container_images.label, deployment_container_services.name") )
                else
                  @deployment.services.where(is_load_balancer: false).joins(:container_image).order( Arel.sql("container_images.label, deployment_container_services.name") )
                end

    respond_to do |format|
      format.html { render template: "container_services/index", layout: !request.xhr? }
      format.json { render json: @services }
      format.xml { render xml: @services }
    end
  end

end
