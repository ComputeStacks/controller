##
# Locations API
#
class Api::LocationsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :project_read }, unless: :current_user

  before_action :find_location, except: %w(index)

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
  #
  def index
    @locations = paginate Location.sorted
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
  #
  def show; end

  private

  def find_location
    @location = Location.find_by(id: params[:id])
    return api_obj_missing if @location.nil?
  end

end
