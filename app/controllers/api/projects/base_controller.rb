class Api::Projects::BaseController < Api::ApplicationController
  api_scope read: :project_read, write: :project_write

  before_action :find_deployment

  private

  def find_deployment
    @deployment = Deployment.find_for(current_user, id: params[:project_id])
    api_obj_missing(["Unknown project"]) if @deployment.nil?
  end
end
