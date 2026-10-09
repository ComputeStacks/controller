##
# The node's maintenance actions on its edit page. Every change to the controller hold
# goes through NodeServices::MaintenanceRequestService.
class Admin::Nodes::MaintenanceController < Admin::Nodes::BaseController
  # AgentWorkers::MaintenanceDriftWorker#refresh! results other than :ok.
  REFRESH_ALERTS = {
    no_token: "no agent token; nothing to ask.",
    locked: "the agent is being updated right now; try again shortly.",
    unreachable: "could not reach the agent.",
    unsupported: "the agent is older than 3.4 and does not support maintenance; the controller hold is not enforced on the node.",
    error: "the agent returned an unexpected response."
  }.freeze

  # Enter maintenance: place the controller hold.
  def create
    maint = request_maintenance(on: true, reason: params[:reason])
    if maint.changed? && @node.region.has_clustered_storage?
      NodeWorkers::EvacuateNodeWorker.perform_async @node.global_id, maint.event&.audit&.global_id
    end
    if params[:customer_message].present?
      # Set after the request, so the node is already in maintenance and the notice is accepted.
      notice = NodeServices::CustomerNoticeService.new(
        @node.reload,
        notice: params[:customer_message],
        actor: current_user,
        remote_ip: request.remote_ip
      )
      unless notice.perform
        return redirect_to(edit_path, alert: "Maintenance requested for #{@node.label}, but the customer message was not saved: #{notice.errors.join(" ")}")
      end
    end
    redirect_to edit_path, notice: "Maintenance requested for #{@node.label}."
  end

  # Release the controller hold. A hold the node placed itself stays.
  def destroy
    was_requested = @node.maintenance_requested
    request_maintenance(on: false)
    @node.update_column(:job_status, "idle") if was_requested
    notice = if @node.maintenance_local_hold
      "Controller hold released. #{@node.label} is still held in maintenance by the node itself."
    else
      "Controller hold released for #{@node.label}."
    end
    redirect_to edit_path, notice: notice
  end

  # Override: release BOTH holds, including the node's own.
  def release_all
    was_requested = @node.maintenance_requested
    request_maintenance(on: false, override_all: true)
    @node.update_column(:job_status, "idle") if was_requested
    redirect_to edit_path, notice: "Releasing all maintenance holds on #{@node.label}."
  end

  # A live GET of the agent's maintenance state, projected and stored the same
  # way the drift worker does it.
  def refresh
    if @node.agent_token.blank?
      return redirect_to(edit_path, alert: "#{@node.label} has no agent token; nothing to ask.")
    end
    result = AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
    alert = REFRESH_ALERTS[result]
    if result == :ok
      redirect_to edit_path, notice: "Refreshed maintenance state from #{@node.label}'s agent."
    else
      redirect_to edit_path, alert: "#{@node.label}: #{alert || "refresh failed (#{result})."}"
    end
  rescue => e
    redirect_to edit_path, alert: "Could not reach #{@node.label}'s agent: #{e.message}"
  end

  private

  def request_maintenance(on:, reason: nil, override_all: false)
    maint = NodeServices::MaintenanceRequestService.new(
      @node,
      on: on,
      reason: reason,
      override_all: override_all,
      actor: current_user,
      remote_ip: request.remote_ip
    )
    maint.perform
    maint
  end

  def edit_path
    "/admin/nodes/#{@node.id}/edit"
  end
end
