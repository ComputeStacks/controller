##
# Project SSH Containers (Bastions)
class Api::Projects::BastionsController < Api::Projects::BaseController

  before_action :find_bastion, only: :show

  ##
  # List Bastions
  #
  # `GET /api/projects/{project-id}/bastions`
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
    @bastions = paginate @deployment.sftp_containers
    respond_to do |format|
      format.any(:json, :xml) { render template: 'api/bastions/index' }
    end
  end

  ##
  # View Bastion
  #
  # `GET /api/projects/{project-id}/bastions/{id}`
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
    @bastion = @deployment.sftp_containers.find_by(id: params[:id])
    return api_obj_missing(["Unknown sftp container"]) if @bastion.nil?
  end

end
