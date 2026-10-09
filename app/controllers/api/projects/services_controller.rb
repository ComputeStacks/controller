##
# Project Container Services API
class Api::Projects::ServicesController < Api::Projects::BaseController
  ##
  # List all services in this project
  #
  # `GET /api/projects/{project-id}/services`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `container_services`: Array<ContainerService> | Each includes `node_status`; see
  #   `GET /api/container_services/{id}`.
  #
  def index
    @services = paginate @deployment.services.where(is_load_balancer: false).sorted.preload(containers: :node, region: :nodes)
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/container_services/index" }
    end
  end
end
