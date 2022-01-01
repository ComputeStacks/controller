class Admin::Containers::BaseController < Admin::ApplicationController

  before_action :load_container

  private

  def load_container
    @container = Deployment::Container.find_by(id: params[:container_id])
    return(redirect_to("/admin/deployments", alert: "Unknown Container")) if @container.nil?
    @deployment = @container.deployment
  end

end