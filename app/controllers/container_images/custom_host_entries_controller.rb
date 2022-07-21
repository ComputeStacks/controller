class ContainerImages::CustomHostEntriesController < ContainerImages::BaseController

  include RescueResponder

  before_action :find_entry, only: [:edit, :update, :destroy]

  def index
    @entries = @image.host_entries
  end

  def new
    @entry = @image.host_entries.new
  end

  def edit; end

  def create
    @entry = @image.host_entries.new entry_params

    if @entry.save
      redirect_to "/container_images/#{@image.id}"
    else
      render :new
    end
  end

  def update
    if @entry.update entry_params
      redirect_to "/container_images/#{@image.id}"
    else
      render :edit
    end
  end

  def destroy
    if @entry.destroy
      flash[:success] = "Entry destroyed"
    else
      flash[:alert] = "Error deleting: #{@entry.errors.full_messages.join(' ')}"
    end
    redirect_to "/container_images/#{@image.id}"
  end

  private

  def entry_params
    params.require(:container_image_custom_host_entry).permit(:hostname, :source_image_id)
  end

  def find_entry
    @entry = @image.host_entries.find params[:id]
    @entry.current_user = current_user
  end

end
