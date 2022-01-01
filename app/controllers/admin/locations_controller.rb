class Admin::LocationsController < Admin::ApplicationController

  before_action :load_location, except: %w(index new create)

  def index
    @locations = Location.sorted
  end

  def show; end

  def new
    @location = Location.new
  end

  def edit; end

  def update
    if @location.update(location_params)
      redirect_to "/admin/locations", notice: "#{@location.name} successfully updated."
    else
      render template: "admin/locations/edit"
    end
  end

  def create
    @location = Location.new(location_params)
    @location.current_user = current_user
    if @location.save
      redirect_to "/admin/locations", notice: "#{@location.name} successfully created."
    else
      render template: "admin/locations/new"
    end
  end

  def destroy
    if @location.destroy
      redirect_to "/admin/locations", notice: "#{@location.name} successfully deleted."
    else
      redirect_to "/admin/locations", alert: "#{@location.errors.full_messages.join(', ')}"
    end
  end

  private

  def location_params
    params.require(:location).permit(
      :name, :active, :fill_strategy, :fill_by_qty, :overcommit_memory, :overcommit_cpu
    )
  end

  def load_location
    @location = Location.find_by(id: params[:id])
    if @location.nil?
      redirect_to "/admin/locations", alert: "Unknown Region."
      return false
    end
    @location.current_user = current_user
  end

end
