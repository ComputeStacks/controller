class Api::Zones::BaseController < Api::ApplicationController
  api_scope read: :dns_read, write: :dns_write

  before_action :find_zone

  private

  def find_zone
    @dns_zone = Dns::Zone.find_for_edit current_user, id: params[:zone_id]
    return api_obj_missing if @dns_zone.nil?
    @dns_zone.current_user = current_user
  end
end
