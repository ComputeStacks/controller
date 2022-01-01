##
# Image Relationships
class Api::ContainerImages::ImageRelationshipsController < Api::ContainerImages::BaseController

  before_action :find_rel, only: [:show, :update, :destroy]

  ##
  # List all image relationships
  #
  # `GET /api/container_images/{container-image-id}/image_relationships`
  #
  #  **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `image_relationships`: Array
  #     * `container_image_id`: Integer
  #     * `requires_container_id`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @image_relationships = @image.dependency_parents
  end

  ##
  # Show a container image relationship
  #
  # `GET /api/container_images/{container-image-id}/image_relationships/{id}`
  #
  #  **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `image_relationship`: Object
  #     * `container_image_id`: Integer
  #     * `requires_container_id`: Integer
  #     * `created_at`: DateTime
  #
  def show; end

  ##
  # Update a container image relationship
  #
  # `PATCH /api/container_images/{container-image-id}/image_relationships/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_relationship`: Object
  #     * `requires_container_id`: Integer
  #
  def update
    if @rel.update(rel_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @rel.errors.full_messages
    end
  end

  ##
  # Create a container image relationship
  #
  # `POST /api/container_images/{container-image-id}/image_relationships`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_relationship`: Object
  #     * `requires_container_id`: Integer
  #
  def create
    @rel = @image.dependency_parents.new(rel_params)
    @rel.current_user = current_user
    if @rel.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @rel.errors.full_messages
    end
  end

  ##
  # Delete a container image relationship
  #
  # `DELETE /api/container_images/{container-image-id}/image_relationships/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @rel.destroy ? api_obj_destroyed : api_obj_error(@rel.errors.full_messages)
  end

  private

  def find_rel
    @rel = @image.dependency_parents.find_by(id: params[:id])
    return api_obj_missing if @rel.nil?
    @rel.current_user = current_user
  end

  def rel_params
    params.require(:image_relationship).permit(:requires_container_id)
  end

end
