##
# Migrate service between versions
class Api::ContainerServices::VariantController < Api::ContainerServices::BaseController
  
  api_scope index: :project_read, create: :project_write

  ##
  # List Available variants
  # 
  # `GET /api/container_services/{container-service-id}/variant`
  # 
  # * `image_variants`: Array<Object>
  #     * `id`: Integer
  #     * `label`: String
  #     * `is_default`: Boolean
  #     * `active`: Boolean | Current active variant
  #
  def index; end

  ##
  # Change service version
  # 
  # `POST /api/container_services/{container-service-id}/variant`
  # 
  # * `variant_id`: Integer
  # * `callback`: Object
  #     * `authorization`: String
  #     * `url`: String
  #
  def create
    # Validation
    unless @service.container_image.image_variants.pluck(:id).include?(variant_params[:variant_id].to_i)
      return api_obj_error(["Invalid variant ID"])
    end
    
    # Apply change
    # ...but skip callbacks, because we need to apply that manually.
    previous_image_variant = @service.image_variant.id
    @service.skip_variant_migration = true
    @service.update image_variant_id: variant_params[:variant_id]
    audit = Audit.create_from_object! @service, "updated", request.remote_ip, current_user
    ContainerServiceWorkers::VariantMigrationWorker.perform_async @service.id, audit.id, previous_image_variant, variant_params[:callback].to_hash
  end

  private

  def variant_params
    params.permit(:variant_id, callback: {})
  end

end
