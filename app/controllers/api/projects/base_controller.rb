class Api::Projects::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :find_deployment

  private

  def find_deployment
    @deployment = Deployment.find_for(current_user, id: params[:project_id])
    return api_obj_missing(["Unknown project"]) if @deployment.nil?
  end

end
