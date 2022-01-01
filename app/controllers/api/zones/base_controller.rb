class Api::Zones::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :dns_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :dns_write }, only: %i[update create destroy], unless: :current_user

  before_action :find_zone

  private

  def find_zone
    @dns_zone = Dns::Zone.find_for_edit current_user, id: params[:zone_id]
    return api_obj_missing if @dns_zone.nil?
    @dns_zone.current_user = current_user
  end

end
