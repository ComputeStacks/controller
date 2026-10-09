##
# Service Containers
class Api::ContainerServices::ContainersController < Api::ContainerServices::BaseController
  ##
  # List Containers
  #
  # `GET /api/container_services/{container-service-id}/containers`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `containers`: Array<Container> | Each includes `node_status`; see `GET /api/containers/{id}`.
  #
  def index
    @containers = @service.containers.sorted.preload(:node)
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/containers/index" }
    end
  end
end
