class Admin::ContainerImageCollectionsController < Admin::ApplicationController

  include RescueResponder

  before_action :find_collection, only: %i[show edit update destroy]
  before_action :get_image_list, only: %i[new create edit update]

  def index
    @collections = ContainerImageCollection.available
  end

  def show; end

  def edit; end

  def new
    @collection = ContainerImageCollection.new
  end

  def create
    @collection = ContainerImageCollection.new(image_collection_params)
    if @collection.save
      redirect_to "/admin/container_image_collections/#{@collection.id}/container_image/new"
    else
      render :new
    end
  end

  def update
    if @collection.update(image_collection_params)
      redirect_to "/admin/container_image_collections"
    else
      render :edit
    end
  end

  def destroy
    unless @collection.destroy
      flash[:alert] = "Error #{@collection.errors.join(" ")}"
    end
    redirect_to "/admin/container_image_collections"
  end

  private

  def get_image_list
    @images = ContainerImage.is_public
  end

  def image_collection_params
    params.require(:container_image_collection).permit(:label, :active, :sort, :add_image_id)
  end

  def find_collection
    @collection = ContainerImageCollection.find params[:id]
  end

  def not_found_responder
    redirect_to "/admin/container_image_collections", alert: "Unknown Collection"
  end

end
