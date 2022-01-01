class Admin::LoadBalancers::DeployLoadBalancerController < Admin::ApplicationController

  before_action :find_load_balancer

  def create
    if @load_balancer.active?
      LoadBalancerServices::DeployConfigService.new(@load_balancer).perform
      flash[:notice] = 'Load Balancer will be re-deployed shortly.'
    elsif !@load_balancer.has_shared_cert?
      flash[:alert] = "Missing SSL Certificate, unable to deploy."
    elsif !@load_balancer.domain_valid
      flash[:alert] = "Domain is currently invalid, triggering validation job now. Please try deploying again in a few minutes."
      current_audit = Audit.create_from_object! @load_balancer, 'updated', current_user.last_request_ip, current_user
      LoadBalancerWorkers::ValidateDomainWorker.perform_async @load_balancer.id, current_audit.id
    else
      flash[:alert] = "Fatal error has prevented this load balancer from deploying."
    end
    redirect_to '/admin/load_balancers'
  end

  private

  def find_load_balancer
    @load_balancer = LoadBalancer.find_by(id: params[:load_balancer_id])
    if @load_balancer.nil?
      redirect_to '/admin/load_balancers', alert: 'Not found.'
      return false
    end
  end

end
