class Containers::PowerManagementController < Containers::BaseController

  def update
    audit = Audit.create_from_object!(@container, 'updated', request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@container, params[:id], audit)
    result = power_action.perform
    if result
      redirect_to @service_base_url, notice: "Command queued."
    else
      redirect_to @service_base_url, alert: power_action.errors.empty? ? "There was a problem performing this job" : power_action.errors.join(' ')
    end
  end


end
