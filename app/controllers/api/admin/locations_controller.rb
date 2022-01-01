##
# # Locations
class Api::Admin::LocationsController < Api::Admin::ApplicationController

  before_action :find_location, except: %i[ index create ]


  ##
  # List All Locations
  #
  # `GET /api/admin/locations`
  #
  # * `locations`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `fill_strategy`: String - `least` or `full`. `Full` will fill to the `fill_to` variable on the region (AZ).
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @locations = Location.all.sorted
    respond_to :json, :xml
  end

  ##
  # View Location
  #
  # `GET /api/admin/locations/{id}`
  #
  # * `location`: Object
  #     * `id`: Integer
  #     * `name`: String
  #     * `fill_strategy`: String - `least` or `full`. `Full` will fill to the `fill_to` variable on the region (AZ).
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show
    respond_to :json, :xml
  end

  ##
  # Update Location
  #
  # `PATCH /api/admin/locations/{id}`
  #
  # * `location`: Object
  #     * `name`: String
  #     * `fill_strategy`: String - `least` or `full`. `Full` will fill to the `fill_to` variable on the region (AZ).

  def update
    return api_obj_error(@location.errors.full_messages) unless @location.update(location_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Location
  #
  # `POST /api/admin/locations`
  #
  # * `location`: Object
  #     * `name`: String
  #     * `fill_strategy`: String - `least` or `full`. `Full` will fill to the `fill_to` variable on the region (AZ).

  def create
    @location = Location.new location_params
    @location.current_user = current_user
    return api_obj_error(@location.errors.full_messages) unless @location.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Location
  #
  # `DELETE /api/admin/locations/{id}`

  def destroy
    return api_obj_error(@location.errors.full_messages) unless @location.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def location_params
    params.require(:location).permit(
      :name, :active, :fill_strategy
    )
  end

  def find_location
    @location = Location.find_by id: params[:id]
    return api_obj_missing if @location.nil?
    @location.current_user = current_user
  end


end
