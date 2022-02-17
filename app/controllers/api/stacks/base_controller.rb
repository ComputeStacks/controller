class Api::Stacks::BaseController < ActionController::Base

  before_action :load_resource

  private

  def load_resource
    response = ClusterAuthService.new(request.headers['Authorization']&.gsub("Bearer ", "").strip)
    if response.node || response.container
      @node = response.node.nil? ? response.container.node : response.node
      @load_balancer = response.load_balancer if response.load_balancer
      @container = response.container if response.container
      @deployment = response.project if response.project
      @service = response.service if response.service
    else
      render json: {errors: ["Invalid authentication header"]}, status: :forbidden
    end
  end

end
