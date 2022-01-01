class Api::Containers::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_container

  private

  def load_container
    @container = Deployment::Container.find_for(current_user, id: params[:container_id])
    return api_obj_missing(["Unknown container"]) if @container.nil?
  end

end
