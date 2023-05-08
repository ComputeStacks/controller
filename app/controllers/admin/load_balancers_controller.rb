class Admin::LoadBalancersController < Admin::ApplicationController

  before_action :find_load_balancer, except: %w(index new create)

  def index
    @load_balancers = LoadBalancer.sorted
  end

  def show
    if request.xhr?
      render layout: false, plain: I18n.l(@load_balancer.job_performed)
    end
  end

  def new
    @load_balancer = LoadBalancer.new(domain_valid: false)
    @regions = Region.sorted
    # @regions = Region.where("load_balancers.region_id != regions.id").joins(:load_balancers).order("lower(regions.name)")
    # if @regions.empty?
    #   redirect_to "/admin/load_balancers", alert: "There are no free regions."
    # end
  end

  def edit
    @load_balancer.external_ips = @load_balancer.ext_ip.join(',')
    @load_balancer.internal_ips = @load_balancer.internal_ip.join(',')
    @regions = Region.sorted
  end

  def update
    @regions = Region.sorted
    if @load_balancer.update(network_params)
      redirect_to "/admin/load_balancers", notice: "#{@load_balancer.label} successfully updated."
    else
      render template: "admin/load_balancers/edit"
    end
  rescue => e
    ExceptionAlertService.new(e, 'd5598a176c476394', current_user).perform
    redirect_to "/admin/load_balancers", alert: "Fatal Error: #{e.message}"
  end

  def create
    @regions = Region.sorted
    @load_balancer = LoadBalancer.new(network_params)
    @load_balancer.current_user = current_user
    @load_balancer.domain_valid = false
    if @load_balancer.valid? && @load_balancer.save
      redirect_to "/admin/load_balancers", notice: "#{@load_balancer.label} successfully updated."
    else
      render template: "admin/load_balancers/new"
    end
  rescue => e
    ExceptionAlertService.new(e, 'cc2fe84d8b431644', current_user).perform
    redirect_to "/admin/load_balancers", alert: "Fatal Error: #{e.message}"
  end

  def destroy
    if @load_balancer.destroy
      redirect_to "/admin/load_balancers", notice: "#{@load_balancer.label} successfully deleted."
    else
      redirect_to "/admin/load_balancers", alert: "Failed to delete #{@load_balancer.label}."
    end
  end

  private

  def network_params
    params.require(:load_balancer).permit(
        :label, :status, :region_id, :le,
        :internal_ips, :external_ips, :public_ip,
        :domain, :shared_certificate, :cpus, :maxconn,
        :maxconn_c, :ssl_cache, :direct_connect, :max_queue,
        :g_timeout_connect, :g_timeout_client, :g_timeout_server,
        :proto_alpn, :proto_11, :proto_20, :proto_23
    )
  end

  def find_load_balancer
    @load_balancer = LoadBalancer.find_by(id: params[:id])
    if @load_balancer.nil?
      redirect_to "/admin/load_balancers", alert: "Load Balancer not found."
      return false
    end
    @load_balancer.current_user = current_user
  end
end
