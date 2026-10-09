##
# # Node Maintenance Override
class Api::Admin::Locations::Regions::Nodes::MaintenanceReleaseAllController < Api::Admin::Locations::Regions::Nodes::BaseController
  ##
  # Release All Maintenance Holds
  #
  # `POST /api/admin/locations/{location_id}/regions/{region_id}/nodes/{node_id}/maintenance/release_all`
  #
  # Releases the controller hold AND the node's own hold (`cs-agent maintenance on`). Use
  # it for a node that was left in maintenance by someone who is no longer around; whoever
  # placed the local hold is not asked. The override is audited and raises a warning-level
  # system event.
  #
  # * `confirm`: Boolean - must be `true`
  #
  # Returns `HTTP 202 Accepted`, with the same body as `POST .../maintenance`. The node
  # leaves maintenance once its agent applies the override; until then
  # `maintenance_status.warnings` includes `override_pending`.
  #
  # Returns `HTTP 422` without `confirm=true`.

  def create
    unless ActiveModel::Type::Boolean.new.cast(params[:confirm]) == true
      return api_obj_error("Releasing every hold, including the node's own, requires confirm=true.")
    end
    was_requested = @node.maintenance_requested
    NodeServices::MaintenanceRequestService.new(
      @node,
      on: false,
      override_all: true,
      actor: current_user,
      remote_ip: request.remote_ip
    ).perform
    @node.update_column(:job_status, "idle") if was_requested
    body = Nodes::MaintenanceStatusPresenter.new(@node).write_response
    respond_to do |f|
      f.json { render json: body, status: :accepted }
      f.xml { render xml: body, status: :accepted }
    end
  end
end
