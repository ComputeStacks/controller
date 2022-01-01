class Api::ContainerServices::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :projects_write }, only: %i[update create destroy], unless: :current_user

  before_action :load_service

  private

    ##
    # =Load service helper
    #
    # Load the service for all sub-controllers.
    #
    def load_service # :doc:
      @service = Deployment::ContainerService.find_for(current_user, id: params[:container_service_id])
      return api_obj_missing if @service.nil?
    end

end
