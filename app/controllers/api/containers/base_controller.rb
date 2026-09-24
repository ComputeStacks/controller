class Api::Containers::BaseController < Api::ApplicationController
  api_scope read: :project_read, write: :project_write

  before_action :load_container

  private

  def load_container
    @container = Deployment::Container.find_for(current_user, id: params[:container_id])
    api_obj_missing(["Unknown container"]) if @container.nil?
  end
end
