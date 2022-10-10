##
# Container Image Variants
class Api::ContainerImages::ImageVariantsController < Api::ContainerImages::BaseController

  before_action :find_variant, only: %i[update destroy]

  ##
  # Create Image Variant
  #
  # `POST /api/container_images/{container-image-id}/image_variants`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_variant`: Object
  #     * `label`: String
  #     * `registry_image_tag`: String | e.g. 'latest'
  #     * `is_default`: Boolean
  #     * `version`: Integer | Sorting position in drop down list. Lower = higher in the list
  #     * `before_migrate`: String | Command to run inside container before moving between versions
  #     * `after_migrate`: String | Command to run inside container after moving between versions
  #     * `rollback_migrate: String` | Command to run inside container when the before script fails.
  #
  def create
    @variant = @image.image_variants.new(variant_params)
    @variant.current_user = current_user
    if @variant.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @variant.errors.full_messages
    end
  end

  ##
  # Update Image Variant
  #
  # `PATCH /api/container_images/{container-image-id}/image_variants/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_variant`: Object
  #     * `label`: String
  #     * `registry_image_tag`: String | e.g. 'latest'
  #     * `is_default`: Boolean
  #     * `version`: Integer | Sorting position in drop down list. Lower = higher in the list
  #     * `before_migrate`: String | Command to run inside container before moving between versions
  #     * `after_migrate`: String | Command to run inside container after moving between versions
  #     * `rollback_migrate: String` | Command to run inside container when the before script fails.
  #
  def update
    if @variant.update(variant_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @variant.errors.full_messages
    end
  end

  ##
  # Delete an image variant
  #
  # `DELETE /api/container_images/{container-image-id}/image_variants/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @variant.destroy ? api_obj_destroyed : api_obj_error(@variant.errors.full_messages)
  end

  private

  def find_variant
    @variant = @image.image_variants.find_by id: params[:id]
    return api_obj_missing if @variant.nil?
    @variant.current_user = current_user
  end

  def variant_params
    params.require(:image_variant).permit(
      :label,
      :registry_image_tag,
      :is_default,
      :version,
      :before_migrate,
      :after_migrate,
      :rollback_migrate
    )
  end

end
