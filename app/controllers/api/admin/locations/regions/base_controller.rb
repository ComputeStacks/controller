class Api::Admin::Locations::Regions::BaseController < Api::Admin::Locations::BaseController

  # noinspection RubyResolve
  before_action :find_region

  private

  def find_region
    @region = @location.regions.find_by(id: params[:region_id])
    return api_obj_missing if @region.nil?
    @region.current_user = current_user
  end

end
