class Admin::ContainersController < Admin::ApplicationController

  before_action :load_container, only: %w(show update)

  def show; end

  def update; end

  private

  def load_container
    @container = Deployment::Container.find_by(id: params[:id])
    return(redirect_to("/admin/deployments", alert: "Unknown Container")) if @container.nil?
    @deployment = @container.deployment
  end

end
