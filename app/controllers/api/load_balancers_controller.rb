##
# LoadBalancer API
class Api::LoadBalancersController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :projects_read }, unless: :current_user

  before_action :find_load_balancer, only: %i[show]

  ##
  # List your load balancers
  #
  # `GET /api/load_balancers`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `load_balancers`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `public_ip`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @load_balancers = paginate current_user.load_balancers
  end

  ##
  # View Load Balancer
  #
  # `GET /api/load_balancers/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `load_balancer`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `public_ip`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  private

  def find_load_balancer
    @load_balancer = current_user.load_balancers.find_by(id: params[:id])
    return api_obj_missing if @load_balancer.nil?
  end

end
