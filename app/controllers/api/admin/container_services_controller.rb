##
# # Container Services
class Api::Admin::ContainerServicesController < Api::Admin::ApplicationController

  ##
  # List All Container Services
  #
  # `GET /api/admin/container_services`
  #
  # add `?all=true` to include same data as in end-user api.
  #
  # * `container_services`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `project`: Object
  #         * `id`: Integer
  #         * `name`: String
  #     * `user`
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object
  #
  def index
    @container_services = paginate Deployment::ContainerService.all.sorted
    respond_to :json, :xml
  end

  ##
  # Get Container Service
  #
  # `GET /api/admin/container_services/{id}`
  #
  # Will return the same schema as the end-user api.
  #
  def show
    @container_service = Deployment::ContainerService.find_by id: params[:id]
    return api_obj_missing if @container_service.nil?
    respond_to :json, :xml
  end

end
