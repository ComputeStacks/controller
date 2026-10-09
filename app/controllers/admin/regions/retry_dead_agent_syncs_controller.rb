##
# "Retry dead" on the availability zone page: revive the region's dead agent syncs
# (agent_pending_syncs that gave up) with a fresh attempt budget, and replay them now.
class Admin::Regions::RetryDeadAgentSyncsController < Admin::ApplicationController
  def create
    @region = Region.find_by id: params[:region_id]

    if @region.nil?
      redirect_to "/admin/regions", alert: "Region not found."
      return false
    end

    revived = AgentPendingSync.where(region_id: @region.id).where.not(dead_at: nil).update_all(
      dead_at: nil, attempts: 0, first_attempted_at: nil, next_attempt_at: Time.current, updated_at: Time.current
    )
    if revived.positive?
      Audit.create_from_object!(@region, "updated", request.remote_ip, current_user)
      AgentWorkers::PendingSyncWorker.perform_async @region.id
    end

    redirect_to "/admin/regions/#{@region.id}", notice: "#{ActionController::Base.helpers.pluralize(revived, "dead agent sync")} queued for retry."
  end
end
