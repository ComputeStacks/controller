class Containers::BaseController < AuthController

  include RescueResponder

  before_action :find_container

  private

  def find_container
    @container = Deployment::Container.find_for_edit(current_user, id: params[:container_id])
    if @container.nil?
      return redirect_to("/deployments", alert: "unknown resource")
    end
    # Reduce load time since we won't use these variables with polling json
    unless request.xhr?
      @deployment = @container.deployment
      @service = @container.service
      @service_base_url = "/container_services/#{@container.service.id}"
    end
  end

  def not_found_responder
    redirect_to "/deployments", alert: "Unknown Container"
  end

end
