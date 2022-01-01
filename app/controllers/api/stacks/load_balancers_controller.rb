# @deprecated
class Api::Stacks::LoadBalancersController < Api::Stacks::BaseController

  # GET /stacks/load_balancers
  def index
    if @load_balancer.nil? || @node.nil?
      render plain: '', status: :not_found
      return false
    end
    stream = render_to_string(template: "api/stacks/load_balancers/config")
    send_data(stream, type: "text/plain", filename: "main.cfg")
  end

  # POST /stacks/load_balancers/provision
  def provision
    if @load_balancer.nil?
      render plain: '', status: :not_found
      return false
    end
    LoadBalancerServices::DeployConfigService.new(@load_balancer).perform
    render plain: 'ok', status: :ok
  end

  # GET /stacks/load_balancers/assets/:file
  def assets
    if @load_balancer.nil?
      render plain: '', status: :not_found
      return false
    end
    if params[:file].nil? || !%w(default).include?(params[:file])
      render plain: '', status: :not_found
      return false
    end
    case params[:file]
    when 'default'
      send_file("#{Rails.root}/app/views/api/stacks/load_balancers/v1/haproxy.html")
    end
  end

end
