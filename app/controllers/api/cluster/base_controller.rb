class Api::Cluster::BaseController < ActionController::Base

  before_action :authenticate_resource!

  respond_to :json

  private

  def authenticate_resource!
    response = ClusterAuthService.new(request.headers['Authorization']&.gsub("Bearer ", "")&.strip)
    if response.node
      @node = response.node
      @load_balancer = nil
      LoadBalancer.all.each do |i|
        @load_balancer = i if i.ext_ip.include?(@node.primary_ip)
      end
    elsif response.container
      @container = response.container
      @service = response.service
      @project = response.project
    else
      render json: {errors: ["Invalid authentication header"]}, status: :forbidden
      return false
    end
  end

end
