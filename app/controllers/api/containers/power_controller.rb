##
# Container Power Management
class Api::Containers::PowerController < Api::Containers::BaseController
  ##
  # Power Control
  #
  # `PUT /api/containers/{container-id}/power/{action}`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # * `action`: String<start,stop,restart,rebuild>
  #
  # This endpoint takes no callback; poll the event instead. (The service-level power
  # endpoint accepts one.)
  #
  # Responds `202 Accepted` with:
  #
  # * `event_id`: Integer
  # * `deferred`: Boolean | true when the node is in maintenance: the action is parked
  #   and runs on the same event once maintenance ends.
  # * `code`: String | `node_maintenance`, only when `deferred` is true
  # * `node_status`: Object | the container's node status, only when `deferred` is true
  #
  # If another action is already in progress on the container, the response is still
  # `202` with `deferred: false`, but that event is canceled ("Action already in progress").
  #
  # Latest request wins: a parked request is replaced by a later one for the same
  # container, and the replaced one is canceled; if it carried a callback (from the
  # service-level endpoint), that callback fires as a failure (Superseded).
  #
  # When the node is offline (or the container has no node), the response is
  # `409 Conflict` with `errors`, `code: "node_offline"` and `node_status`. Other failures
  # are `422 Unprocessable Entity` with `errors`.
  #
  def update
    allowed_actions = %w[start stop restart rebuild]
    unless allowed_actions.include?(params[:id])
      return api_obj_error(["Unknown action.", "Available actions are: #{allowed_actions.join(", ")}"])
    end
    audit = Audit.create_from_object!(@container, "updated", request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@container, params[:id], audit)
    result = power_action.perform
    case power_action.outcome
    when :refused_offline
      errors = power_action.errors.presence || ["The node hosting this container is offline."]
      return api_node_unavailable(errors, code: "node_offline", node_status: Nodes::CustomerStatusPresenter.for_node(@container.node))
    when :deferred
      body = {
        event_id: power_action.event&.id,
        deferred: true,
        code: "node_maintenance",
        node_status: Nodes::CustomerStatusPresenter.for_node(@container.node)
      }
    else
      return api_obj_error(power_action.errors) unless result
      body = {event_id: power_action.event&.id, deferred: false}
    end
    respond_to do |f|
      f.json { render json: body, status: :accepted }
      f.xml { render xml: body, status: :accepted }
    end
  rescue => e
    api_fatal_error(e, "7f43b33a451be71f")
  end
end
