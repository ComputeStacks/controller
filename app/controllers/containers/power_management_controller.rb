class Containers::PowerManagementController < Containers::BaseController
  def update
    audit = Audit.create_from_object!(@container, "updated", request.remote_ip, current_user)
    power_action = PowerCycleContainerService.new(@container, params[:id], audit)
    result = power_action.perform
    case power_action.outcome
    when :deferred
      redirect_to @service_base_url, notice: I18n.t("node_status.power.deferred")
    when :refused_offline
      redirect_to @service_base_url, alert: I18n.t("node_status.power.refused_offline")
    else
      if result
        redirect_to @service_base_url, notice: "Command queued."
      else
        redirect_to @service_base_url, alert: power_action.errors.empty? ? "There was a problem performing this job" : power_action.errors.join(" ")
      end
    end
  end
end
