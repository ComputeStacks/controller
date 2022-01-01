class Api::Admin::Locations::BaseController < Api::Admin::ApplicationController

  before_action :find_location

  private

  def find_location
    @location = Location.find_by id: params[:location_id]
    return api_obj_missing if @location.nil?
    @location.current_user = current_user
  end

end
