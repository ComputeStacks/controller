class ContainerServices::BaseController < AuthController

  before_action :find_service

  private

  def find_service
    @service = Deployment::ContainerService.find_for current_user, { id: params[:container_service_id] }
    if @service.nil?
      return respond_to do |format|
        format.html { redirect_to("/deployments", alert: "Unknown container service") }
        format.json { head :unauthorized }
        format.xml { head :unauthorized }
      end
    end
    @deployment = @service&.deployment
    @project_owner = @deployment.nil? ? current_user : @deployment.user
  end

end
