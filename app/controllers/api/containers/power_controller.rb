##
# Container Power Management
class Api::Containers::PowerController < Api::Containers::BaseController

  ##
  # Power Control
  #
  # `PUT /api/containers/{container-id}/power/{action}`
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
    audit = Audit.create_from_object!(@container, 'updated', request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@container, params[:id], audit)
    result = power_action.perform
    return api_obj_error(power_action.errors) unless result
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  rescue => e
    return api_fatal_error(e, '7f43b33a451be71f')
  end

end
