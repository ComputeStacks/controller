##
# Products API
#
# Available products and pricing
#
class Api::ProductsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, unless: :current_user

  ##
  # List all available products
  #
  # `GET /api/products`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # * `products`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `price`: String
  #     * `cpu`: Decimal
  #     * `term`: `String<hour,month,year>`
  #     * `memory`: Integer
  #     * `bandwidth`: Integer
  #     * `storage`: Integer
  #     * `ipaddr`: Integer
  #     * `backup`: Integer
  #     * `swap`: Integer
  #     * `region`: Integer
  #
  def index
    if request_version < 51
      respond_to do |format|
        format.json { render json: current_user.price_list }
        format.xml { render xml: current_user.price_list  }
      end
    else
      respond_to do |format|
        format.json { render json: current_user.package_list }
        format.xml { render xml: current_user.package_list }
      end
    end
  end

end
