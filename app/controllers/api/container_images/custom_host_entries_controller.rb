##
# Container Image Host Entry
class Api::ContainerImages::CustomHostEntriesController < Api::ContainerImages::BaseController

  before_action :find_entry, only: [:show, :update, :destroy]

  ##
  # List all host entries
  #
  # `GET /api/container_images/{container-image-id}/custom_host_entries`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `host_entries`: Array
  #     * `hostname`: String
  #     * `source_image`: Object
  #         * `id`: Integer
  #         * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @entries = @image.host_entries
  end

  ##
  # View Host Entry
  #
  # `GET /api/container_images/{container-image-id}/custom_host_entries/{id}`
  #
  # **OAuth Authorization Required**: `images_read`, `public`
  #
  # * `host_entries`: Object
  #     * `hostname`: String
  #     * `source_image`: Object
  #         * `id`: Integer
  #         * `label`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show; end

  ##
  # Update Host Entry
  #
  # `PATCH /api/container_images/{container-image-id}/custom_host_entries/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `host_entry`: Object
  #     * `hostname`: String
  #     * `source_image_id`: Integer
  #
  def update
    if @entry.update(entry_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @entry.errors.full_messages
    end
  end

  ##
  # Create Host Entry
  #
  # `POST /api/container_images/{container-image-id}/custom_host_entries`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `host_entry`: Object
  #     * `hostname`: String
  #     * `source_image_id`: Integer
  #
  def create
    @entry = @image.host_entries.new(entry_params)
    @entry.current_user = current_user
    if @entry.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @entry.errors.full_messages
    end
  end

  ##
  # Delete Host Entry
  #
  # `DELETE /api/container_images/{container-image-id}/custom_host_entries/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  def destroy
    @entry.destroy ? api_obj_destroyed : api_obj_error(@entry.errors.full_messages)
  end

  private

  def find_entry
    @entry = @image.host_entries.find_by id: params[:id]
    return api_obj_missing if @entry.nil?
    @entry.current_user = current_user
  end

  def entry_params
    params.require(:host_entry).permit(:hostname, :source_image_id)
  end

end
