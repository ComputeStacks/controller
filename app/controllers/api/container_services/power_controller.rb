##
# Container Service Power Management
class Api::ContainerServices::PowerController < Api::ContainerServices::BaseController
  ##
  # Perform a power action on all containers belonging to a service
  #
  # `PUT /api/container_services/{container-service-id}/power/{action}`
  #
  # **OAuth AuthorizationRequired**: `project_write`
  #
  # * `action`: String<start,stop,restart,rebuild>
  # * `callback`: Object | optional webhook, called when each container's event finishes.
  #   For an action parked for maintenance, that is when the parked action finally runs.
  #     * `authorization`: String
  #     * `url`: String
  #
  # Responds `202 Accepted` with:
  #
  # * `deferred`: Boolean | true if any container's action was parked because its node
  #   is in maintenance; it runs on the same event once maintenance ends.
  # * `code`: String | `node_maintenance` when `deferred` is true, otherwise null
  # * `event_ids`: Array<Integer>
  # * `containers`: Array
  #     * `id`: Integer
  #     * `event_id`: Integer
  #     * `result`: String<queued,deferred,in_progress,refused_offline,failed>
  #       `in_progress`: another action was running, so this one's event was canceled.
  #       `refused_offline`: the node is offline (or the container has no node); canceled.
  #
  # Latest request wins: a parked request is replaced by a later one for the same
  # container, and the replaced one is canceled; if it carried a callback, that callback
  # fires as a failure (Superseded).
  #
  # When the service has containers and every one was refused because its node is
  # offline, the response is `409 Conflict` with `errors`, `code: "node_offline"` and
  # `node_status`. A service with no containers responds `202` with an empty list.
  #
  def update
    allowed_actions = %w[start stop restart rebuild]
    unless allowed_actions.include?(params[:id])
      return api_obj_error(["Unknown action.", "Available actions are: #{allowed_actions.join(", ")}"])
    end
    audit = Audit.create_from_object!(@service, "updated", request.remote_ip, current_user)
    results = @service.containers.map do |container|
      s = PowerCycleContainerService.new(container, params[:id].to_s, audit)
      if params[:callback]
        s.callback_auth = params[:callback][:authorization]
        s.callback_url = params[:callback][:url]
      end
      s.perform
      {id: container.id, event_id: s.event&.id, result: s.outcome.to_s}
    end
    if results.any? && results.all? { |r| r[:result] == "refused_offline" }
      return api_node_unavailable(
        ["The node hosting this service is offline."],
        code: "node_offline",
        node_status: Nodes::CustomerStatusPresenter.for_service(@service)
      )
    end
    deferred = results.any? { |r| r[:result] == "deferred" }
    body = {
      deferred: deferred,
      code: (deferred ? "node_maintenance" : nil),
      event_ids: results.map { |r| r[:event_id] }.compact.uniq,
      containers: results
    }
    respond_to do |f|
      f.json { render json: body, status: :accepted }
      f.xml { render xml: body, status: :accepted }
    end
  rescue => e
    api_fatal_error(e, "f7ece497aadb33bc")
  end
end
