##
# Container Service Bastions
class Api::ContainerServices::BastionsController < Api::ContainerServices::BaseController
  before_action :find_bastion, only: :show

  ##
  # List Bastion Containers
  #
  # `GET /api/container_services/{container-service-id}/bastions`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `bastions`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `status`: String
  #     * `on_latest_image`: Boolean | Read from stored state, refreshed daily.
  #     * `node_id`: Integer
  #     * `ip_addr`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `port`: Integer
  #     * `pw_auth`: Boolean | If true, password auth is enabled.
  #     * `username`: String
  #     * `password`: String
  #     * `node_status`: Object - availability of the node running this bastion. Read from stored state.
  #         * `state`: String<online,maintenance,offline> - worst state among those nodes
  #         * `since`: DateTime | null - when that state began
  #         * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #         * `message`: String | null - operator's notice to customers; null while `online`
  #         * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #             * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #             * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #             * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #
  def index
    @bastions = @service.sftp_containers # an Array
    ActiveRecord::Associations::Preloader.new(records: @bastions, associations: :node).call
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/bastions/index" }
    end
  end

  ##
  # View a single Bastion Container
  #
  # `GET /api/container_services/{container-service-id}/bastions/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `bastion`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `status`: String
  #     * `on_latest_image`: Boolean | Read from stored state, refreshed daily.
  #     * `node_id`: Integer
  #     * `ip_addr`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `port`: Integer
  #     * `pw_auth`: Boolean | If true, password auth is enabled.
  #     * `username`: String
  #     * `password`: String
  #     * `node_status`: Object - availability of the node running this bastion. Read from stored state.
  #         * `state`: String<online,maintenance,offline> - worst state among those nodes
  #         * `since`: DateTime | null - when that state began
  #         * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #         * `message`: String | null - operator's notice to customers; null while `online`
  #         * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #             * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #             * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #             * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #
  def show
    respond_to do |format|
      format.any(:json, :xml) { render template: "api/bastions/show" }
    end
  end

  private

  def find_bastion
    @bastion = @service.deployment.sftp_containers.find_by(id: params[:id])
    api_obj_missing(["Unknown bastion container"]) if @bastion.nil?
  end
end
