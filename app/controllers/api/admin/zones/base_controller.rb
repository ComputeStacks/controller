class Api::Admin::Zones::BaseController < Api::Admin::ApplicationController

  before_action :find_zone

  private

  def find_zone
    @dns_zone = Dns::Zone.find params[:zone_id]
    return api_obj_missing if @dns_zone.nil?
    @dns_zone.current_user = current_user
  end

end
