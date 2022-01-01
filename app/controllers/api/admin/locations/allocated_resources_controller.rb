##
# Display Resource Allocation by Region (Location)
class Api::Admin::Locations::AllocatedResourcesController < Api::Admin::Locations::BaseController

  ##
  # Show Allocation
  #
  # `GET /api/admin/locations/{location_id}/allocated_resources`
  #
  # * `total`: Hash
  #     * `containers`: Integer
  #     * `sftp_containers`: Integer
  #     * `cpu`: Float (CORES)
  #     * `memory`: Integer (MB)
  # * `availability_zones`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `allocated`: Hash
  #         * `containers`: Integer
  #         * `sftp_containers`: Integer
  #         * `cpu`: Float (CORES)
  #         * `memory`: Integer (MB)
  #     * `projects`: Array
  #         * `id`: Integer
  #         * `name`: String

  def index
    respond_to do |format|
      format.json { render json: @location.allocated_resources }
      format.xml { render xml: @location.allocated_resources }
    end
  end

end
