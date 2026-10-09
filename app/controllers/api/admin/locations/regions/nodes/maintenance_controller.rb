##
# # Node Maintenance Status
#
# These endpoints place or release the *controller's* maintenance hold. A node can also
# hold itself in maintenance (`cs-agent maintenance on`); releasing the controller hold
# does not end that one.
class Api::Admin::Locations::Regions::Nodes::MaintenanceController < Api::Admin::Locations::Regions::Nodes::BaseController
  ##
  # Request Maintenance Mode
  #
  # `POST /api/admin/locations/{location_id}/regions/{region_id}/nodes/{node_id}/maintenance`
  #
  # The node stops taking new containers, the controller stops recovering its containers,
  # and its agent pauses backups and other background work. Containers are not moved.
  #
  # * `reason`: String (optional) - internal; never shown to customers
  # * `customer_message`: String (optional) - message to customers with something on this
  #   node, set as the node's `customer_notice` once the hold is placed (see Update Node).
  #   Omit it to leave any existing notice as it is.
  #
  # Returns `HTTP 202 Accepted`; the hold is delivered to the node asynchronously.
  # Repeating the request is safe: it does not bump the generation, and it re-sends the
  # hold to the node.
  #
  # * `maintenance`: Boolean - effective maintenance (controller OR node hold)
  # * `maintenance_requested`: Boolean - the controller hold
  # * `maintenance_gen`: Integer
  # * `maintenance_status`: Object - as on the node (see View Node)

  def create
    NodeServices::MaintenanceRequestService.new(
      @node,
      on: true,
      reason: params[:reason],
      actor: current_user,
      remote_ip: request.remote_ip
    ).perform
    if params.key?(:customer_message)
      @node.reload
      notice = NodeServices::CustomerNoticeService.new(
        @node,
        notice: params[:customer_message],
        actor: current_user,
        remote_ip: request.remote_ip
      )
      return api_obj_error(notice.errors) unless notice.perform
    end
    render_status
  end

  ##
  # Release Maintenance Mode
  #
  # `DELETE /api/admin/locations/{location_id}/regions/{region_id}/nodes/{node_id}/maintenance`
  #
  # Releases the controller hold only. A node that holds itself in maintenance stays in
  # maintenance (`maintenance` remains `true`); see `maintenance/release_all`.
  #
  # `DELETE .../maintenance/{anything}` is also accepted, for older clients.
  #
  # Returns `HTTP 202 Accepted`, with the same body as `POST`.

  def destroy
    was_requested = @node.maintenance_requested
    NodeServices::MaintenanceRequestService.new(
      @node,
      on: false,
      actor: current_user,
      remote_ip: request.remote_ip
    ).perform
    @node.update_column(:job_status, "idle") if was_requested
    render_status
  end

  private

  def render_status
    body = Nodes::MaintenanceStatusPresenter.new(@node).write_response
    respond_to do |f|
      f.json { render json: body, status: :accepted }
      f.xml { render xml: body, status: :accepted }
    end
  end
end
