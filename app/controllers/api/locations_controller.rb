##
# Locations API
#
class Api::LocationsController < Api::ApplicationController
  api_scope read: :project_read

  before_action :find_location, except: %w[index]

  ##
  # List Locations
  #
  # `GET /api/locations`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `locations`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `regions`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `node_status`: Object - status of the availability zone's nodes: those open for placements plus any disabled node still hosting containers (none: `offline`).
  #           Read from stored state.
  #             * `state`: String<online,maintenance,offline> - worst state among those nodes
  #             * `since`: DateTime | null - when that state began
  #             * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #             * `message`: String | null - operator's notice to customers; null while `online`
  #             * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #                 * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #                 * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #                 * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #
  def index
    @locations = paginate Location.sorted.preload(regions: :nodes)
  end

  ##
  # Show Location
  #
  # `GET /api/locations/{id}`
  #
  # **OAuth AuthorizationRequired**: `project_read`
  #
  # * `location`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `regions`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `node_status`: Object - status of the availability zone's nodes: those open for placements plus any disabled node still hosting containers (none: `offline`).
  #           Read from stored state.
  #             * `state`: String<online,maintenance,offline> - worst state among those nodes
  #             * `since`: DateTime | null - when that state began
  #             * `planned`: Boolean - true for maintenance, false for an unplanned outage
  #             * `message`: String | null - operator's notice to customers; null while `online`
  #             * `operations`: Object - what each action does in this state (see doc/maintenance.md)
  #                 * `power`: String<available,deferred,refused> - deferred runs when maintenance ends; latest request wins
  #                 * `backup`, `restore`, `export`, `scale`, `bastion_password_reset`: String<available,refused>
  #                 * `config_changes`: String<available,deferred> - deferred until the node reconnects
  #
  def show
  end

  private

  def find_location
    @location = Location.preload(regions: :nodes).find_by(id: params[:id])
    api_obj_missing if @location.nil?
  end
end
