##
# Container Service Bastions
class Api::ContainerServices::BastionsController < Api::ContainerServices::BaseController

  before_action :find_bastion, only: :show

  ##
  # List Bastion Containers
  #
  # `GET /api/container_services/{container-service-id}/bastions`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `bastions`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `status`: String
  #     * `node_id`: Integer
  #     * `ip_addr`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `port`: Integer
  #     * `pw_auth`: Boolean | If true, password auth is enabled.
  #     * `username`: String
  #     * `password`: String
  #
  def index
    @bastions = @service.sftp_containers
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/bastions/index' }
    end
  end

  ##
  # View a single Bastion Container
  #
  # `GET /api/container_services/{container-service-id}/bastions/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `bastion`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `status`: String
  #     * `node_id`: Integer
  #     * `ip_addr`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `port`: Integer
  #     * `pw_auth`: Boolean | If true, password auth is enabled.
  #     * `username`: String
  #     * `password`: String
  #
  def show
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/bastions/show' }
    end
  end

  private

  def find_bastion
    @bastion = @service.deployment.sftp_containers.find_by(id: params[:id])
    return api_obj_missing(["Unknown bastion container"]) if @bastion.nil?
  end

end
