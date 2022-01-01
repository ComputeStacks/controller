##
# Service Containers
class Api::ContainerServices::ContainersController < Api::ContainerServices::BaseController

  ##
  # List Containers
  #
  # `GET /api/container_services/{container-service-id}/containers`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `containers`: Array<Service>
  #
  def index
    @containers = @service.containers.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/containers/index' }
    end
  end

end
