##
# Container Service Load Balancers
class Api::ContainerServices::LoadBalancersController < Api::ContainerServices::BaseController

  ##
  # List Load Balancers
  #
  # `GET /api/container_services/{container-service-id}/load_balancers`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `load_balancers`: Array<LoadBalancer>
  #
  def index
    @load_balancers = LoadBalancer.where(id: @service.load_balancer.id) # need to get an array
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/load_balancers/index' }
    end
  end

  ##
  # View Load Balancer
  #
  # A service may only have 1 load balancer, so id is ignored.
  #
  # `GET /api/container_services/{container-service-id}/load_balancers/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `load_balancer`: Object<LoadBalancer>
  #
  def show
    @load_balancer = @service.load_balancer
    return api_obj_missing if @load_balancer.nil?
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/load_balancers/show' }
    end
  end

end
