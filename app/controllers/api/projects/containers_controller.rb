##
# List Project Containers
class Api::Projects::ContainersController < Api::Projects::BaseController

  ##
  # List project containers
  #
  # `GET /api/projects/{project-id}/containers`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `containers`: Array<Container>
  #
  def index
    @containers = paginate @deployment.deployed_containers.sorted
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/containers/index' }
    end
  end

end
