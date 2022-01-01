class Api::Admin::Projects::BaseController < Api::Admin::ApplicationController

  before_action :find_deployment

  private

  def find_deployment
    @deployment = Deployment.find params[:project_id]
  end

end
