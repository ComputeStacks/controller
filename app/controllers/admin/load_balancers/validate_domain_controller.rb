class Admin::LoadBalancers::ValidateDomainController < Admin::ApplicationController
  before_action :find_load_balancer

  # Re-queue domain validation by hand, e.g. when the job queued on save was lost.
  def create
    audit = Audit.create_from_object! @load_balancer, "updated", current_user.last_request_ip, current_user
    LoadBalancerWorkers::ValidateDomainWorker.perform_async @load_balancer.id, audit.id
    redirect_to "/admin/load_balancers", notice: "Validating #{@load_balancer.domain}, check the event log for the result."
  end

  private

  def find_load_balancer
    @load_balancer = LoadBalancer.find_by(id: params[:load_balancer_id])
    if @load_balancer.nil?
      redirect_to "/admin/load_balancers", alert: "Not found."
      false
    end
  end
end
