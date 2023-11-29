##
# Container Service Power Management
class Api::ContainerServices::PowerController < Api::ContainerServices::BaseController

  ##
  # Perform a power action on all containers belonging to a service
  #
  # `PUT /api/container_services/{container-service-id}/power/{action}`
  #
  # **OAuth AuthorizationRequired**: `projects_write`
  #
  # * `action`: String<start,stop,restart,rebuild>
  #
  def update
    allowed_actions = %w(start stop restart rebuild)
    unless allowed_actions.include?(params[:id])
      return api_obj_error(["Unknown action.", "Available actions are: #{allowed_actions.join(', ')}"])
    end
    audit = Audit.create_from_object!(@service, 'updated', request.remote_ip, current_user)
    @service.containers.each do |container|
      PowerCycleContainerService.new(container, params[:id].to_s, audit).perform
    end
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.json { render xml: {}, status: :accepted }
    end
  rescue => e
    return api_fatal_error(e, 'f7ece497aadb33bc')
  end

end
