class ContainerServices::HostEntriesController < ContainerServices::BaseController

  include RescueResponder

  before_action :find_entry, except: %i[index new create]
  before_action :set_has_template, only: %i[new create]

  def index
    @entries = @service.host_entries
  end

  def new
    @entry = @service.host_entries.new
  end

  def edit; end

  def create
    @entry = @service.host_entries.new entry_params
    @entry.keep_updated = false
    if @entry.save
      redirect_to "/container_services/#{@service.id}/host_entries"
    else
      render :new
    end
  end

  def update
    if @entry.update update_entry_params
      redirect_to "/container_services/#{@service.id}/host_entries"
    else
      render :edit
    end
  end

  def destroy
    if @entry.destroy
      flash[:success] = "Entry Destroyed"
    else
      flash[:alert] = "Error deleting entry: #{@entry.errors.full_messages.join(' ')}"
    end
    redirect_to "/container_services/#{@service.id}/host_entries"
  end

  private

  def entry_params
    params.require(:container_service_host_entry).permit(:hostname, :ipaddr)
  end

  def update_entry_params
    params.require(:container_service_host_entry).permit(:hostname, :ipaddr, :keep_updated)
  end

  def find_entry
    @entry = @service.host_entries.find params[:id]
    @entry.current_user = current_user
    @has_template = @entry.template&.container_image
  end

  def set_has_template
    @has_template = false
  end

end
