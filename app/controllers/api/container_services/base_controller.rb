class Api::ContainerServices::BaseController < Api::ApplicationController
  api_scope read: :project_read, write: :project_write

  before_action :load_service

  private

  ##
  # =Load service helper
  #
  # Load the service for all sub-controllers.
  #
  def load_service # :doc:
    @service = Deployment::ContainerService.find_for(current_user, id: params[:container_service_id])
    api_obj_missing if @service.nil?
  end
end
