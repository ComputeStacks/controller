##
# Project Container Services API
class Api::Projects::ServicesController < Api::Projects::BaseController

  ##
  # List all services in this project
  #
  # `GET /api/projects/{project-id}/services`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `container_services`: Array<ContainerService>
  # * `container_images`: Array<ContainerImage>
  #
  def index
    @services = paginate @deployment.services.where(is_load_balancer: false).sorted
    @images = []
    @services.each do |s|
      next if s.container_image.nil?
      @images << s.container_image unless @images.include?(s.container_image)
    end
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/container_services/index' }
    end
  end

end
