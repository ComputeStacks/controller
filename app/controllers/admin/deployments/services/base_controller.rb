class Admin::Deployments::Services::BaseController < Admin::Deployments::BaseController

  before_action :find_service

  private

  def find_service
    @service = @deployment.services.find_by(id: params[:service_id])
    return(redirect_to("/admin/deployments/#{@deployment.id}", alert: "Unknown service.")) if @service.nil?
  end

  def base_url
    "/admin/deployments/#{@service.deployment.id}-#{@service.deployment.name.parameterize}/services/#{@service.id}"
  end

end
