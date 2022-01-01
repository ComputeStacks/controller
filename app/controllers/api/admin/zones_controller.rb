##
# List All DNS Zonesx
class Api::Admin::ZonesController < Api::Admin::ApplicationController

  before_action :load_user

  ##
  # List All DNS Zones
  #
  # `GET /api/admin/zones`
  #
  # You may optionally include `?user_id=` to filter zones by user.
  #
  # Returns:
  # * `zones`: Array
  #   * `id`: Integer
  #   * `name`: String
  #   * `user`: Object
  #       * `id`: Integer
  #       * `email`: String
  #       * `external_id`: String
  #       * `labels`: Object
  #   * `created_at`: DateTime
  #   * `updated_at`: DateTime
  #

  def index
    @dns_zones = paginate(@user ? @user.dns_zones : Dns::Zone.all)
    respond_to :json, :xml
  end

  private

  def load_user
    if params[:user_id]
      @user = User.find_by(id: params[:user_id])
      return api_obj_missing if @user.nil?
    end
  end

end
