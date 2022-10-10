class Admin::ContainerImageCollections::ContainerImageController < Admin::ApplicationController

  include RescueResponder

  before_action :find_collection
  before_action :find_image, only: :destroy

  def new; end

  def create
    if @collection.update(image_collection_params)
      redirect_to "/admin/container_image_collections/#{@collection.id}"
    else
      render :new
    end
  end

  def destroy
    unless @collection.container_images.destroy(@image)
      flash[:alert] = "Failed to remove image from collection"
    end
    redirect_to "/admin/container_image_collections/#{@collection.id}"
  end

  private

  def image_collection_params
    params.require(:container_image_collection).permit(:add_image_id)
  end

  def find_collection
    @collection = ContainerImageCollection.find params[:container_image_collection_id]
  end

  def find_image
    @image = @collection.container_images.find params[:id]
  end

  def not_found_responder
    redirect_to "/admin/container_image_collections", alert: "Unknown Collection"
  end

end
