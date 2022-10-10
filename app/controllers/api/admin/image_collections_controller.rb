##
# Admin Image Collections
class Api::Admin::ImageCollectionsController < Api::Admin::ApplicationController

  before_action :find_collection, only: %i[update destroy]

  ##
  # Create Image Collection
  #
  # `POST /api/admin/image_collections`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_collection`: Object
  #     * `label`: String
  #     * `active`: Boolean
  #     * `sort`: Integer | How it's sorted on the order form
  #     * `container_image_ids`: Array<Integer> | List of image IDs
  #
  def create
    @collection = ContainerImageCollection.new collection_params
    @collection.current_user = current_user
    if @collection.save
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :created }
      end
    else
      api_obj_error @collection.errors.full_messages
    end
  end

  ##
  # Update Image Collection
  #
  # `PATCH /api/admin/image_collections/{id}`
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # * `image_collection`: Object
  #     * `label`: String
  #     * `active`: Boolean
  #     * `sort`: Integer | How it's sorted on the order form
  #     * `container_image_ids`: Array<Integer> | List of image IDs
  #
  def update
    if @collection.update(collection_params)
      respond_to do |format|
        format.any(:json, :xml) { render :show, status: :accepted }
      end
    else
      api_obj_error @collection.errors.full_messages
    end
  end

  ##
  # Delete Image Collection
  #
  # **OAuth Authorization Required**: `images_write`
  #
  # `DELETE /api/admin/image_collections/{id}`
  #
  def destroy
    @collection.destroy ? api_obj_destroyed : api_obj_error(@collection.errors.full_messages)
  end

  private

  def collection_params
    params.require(:image_collection).permit(
      :label,
      :active,
      :sort,
      container_image_ids: []
    )
  end

  def find_collection
    @collection = ContainerImageCollection.find_by id: params[:id]
    return api_obj_missing if @collection.nil?
    @collection.current_user = current_user
  end

end
