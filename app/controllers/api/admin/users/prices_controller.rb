##
# Display the prices for a given user.
#
# For API Version < 50, you will get a single region's prices. For newer api methods, all regions and their
# specific pricing is returned.
class Api::Admin::Users::PricesController < Api::Admin::Users::BaseController

  def index
    respond_to do |format|
      if request_version < 50
        format.json { render json: @user.price_list(Region.has_nodes.first) }
        format.xml { render xml: @user.price_list(Region.has_nodes.first)  }
      else
        format.json { render json: @user.price_list }
        format.xml { render xml: @user.price_list  }
      end
    end
  end

end
