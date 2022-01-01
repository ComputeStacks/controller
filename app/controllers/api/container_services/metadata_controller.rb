##
# Container Service MetaData
class Api::ContainerServices::MetadataController < Api::ContainerServices::BaseController

  ##
  # List Container Service Metadata
  #
  # `GET /api/container_services/{container-service-id}/metadata`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `metadata`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String
  #     * `decrypted_value`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @settings = @service.combined_settings
  end

  ##
  # View Metadatum
  #
  # `GET /api/container_services/{container-service-id}/metadata/{id}`
  #
  # **OAuth AuthorizationRequired**: `projects_read`
  #
  # * `metadata`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `label`: String
  #     * `param_type`: String
  #     * `decrypted_value`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show
    # Using deployment here to allow viewing _any_ service belonging to this project.
    # This is to allow easy viewing of custom load balancer params.
    @setting = @service.deployment.setting_params.find(params[:id])
  end

end
