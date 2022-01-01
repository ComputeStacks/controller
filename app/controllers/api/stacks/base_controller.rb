class Api::Stacks::BaseController < ActionController::Base

  before_action :load_resource

  private

  def load_resource
    response = ClusterAuthService.new(request.headers['Authorization']&.gsub("Bearer ", "").strip)
    if response.node || response.container
      @node = response.node.nil? ? response.container.node : response.node
      @load_balancer = nil
      LoadBalancer.all.each do |i|
        @load_balancer = i if i.ext_ip.include?(@node.primary_ip)
      end
      @container = response.container if response.container
      @deployment = response.project if response.project
      @service = response.service if response.service
    else
      render json: {errors: ["Invalid authentication header"]}, status: :forbidden
    end
  end

end
