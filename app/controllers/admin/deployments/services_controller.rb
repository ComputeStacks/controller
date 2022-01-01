class Admin::Deployments::ServicesController < Admin::Deployments::BaseController

  before_action :find_service, only: %w(show)

  def index
    @services = @deployment.services.sorted
    render(template: "admin/deployments/services/index", layout: false) if request.xhr?
  end

  def show; end

  private

  def service_params
    params.require(:deployment_container_service).permit(:label, :master_domain_id, :status, :command, :tag_list, :override_autoremove)
  end

  def find_service
    @service = @deployment.services.find_by(id: params[:id])
    return(redirect_to("/admin/deployments/#{@deployment.id}", alert: "Unknown service.")) if @service.nil?
  end

end
