class Admin::Containers::PowerController < Admin::Containers::BaseController


  # PUT /admin/containers/:container_id/power/:id
  #
  # params[:id] Action to perform (start, stop, restart, rebuild)
  #
  def update
    unless %w(start stop restart rebuild).include?(params[:id])
      redirect_to "/admin/containers/#{@container.id}", alert: "Unknown action."
      return false
    end
    audit = Audit.create_from_object!(@container, 'updated', request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@container, params[:id], audit)
    result = power_action.perform
    if result
      redirect_to "/admin/deployments/#{@deployment.id}", notice: "Command queued."
    else
      redirect_to "/admin/deployments/#{@deployment.id}", alert: power_action.errors.empty? ? "There was a problem performing this job" : power_action.errors.join(' ')
    end
  end

end
