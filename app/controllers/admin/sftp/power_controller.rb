class Admin::Sftp::PowerController < Admin::Sftp::BaseController

  # PUT /admin/sftp/:sftp_id/power/:id
  #
  # params[:id] Action to perform (start, stop, restart, rebuild)
  #
  def update
    unless %w(start stop restart rebuild).include?(params[:id])
      redirect_to "/admin/sftp/#{@container.id}", alert: "Unknown action."
      return false
    end
    audit = Audit.create_from_object!(@container, 'updated', request.remote_ip, current_user)
    power_service = PowerCycleContainerService.new(@container, params[:id], audit)
    if power_service.perform
      redirect_to @container.deployment.nil? ? "/admin/sftp/#{@container.id}" : "/admin/deployments/#{@container.
      deployment.id}#sftp", notice: "Command queued."
    else
      redirect_to @container.deployment.nil? ? "/admin/sftp/#{@container.id}" : "/admin/deployments/#{@container.
      deployment.id}#sftp", alert: power_service.errors.join(' ')
    end
  end


end
