##
# List Project Images
class Api::Projects::ImagesController < Api::Projects::BaseController

  ##
  # List images in use by this project
  #
  # `GET /api/project/{project-id}/images`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `container_images`: Array<ContainerImage>
  #
  def index
    @container_images = paginate @deployment.container_images
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/container_images/index' }
    end
  end

end
