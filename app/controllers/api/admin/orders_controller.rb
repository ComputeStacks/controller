##
# Order
class Api::Admin::OrdersController < Api::Admin::ApplicationController

  before_action :find_order, except: %i[ index create ]

  ##
  # List Orders
  #
  # `GET orders(/filter/:filter)`
  # `GET users/:user_id/orders(/filter/:filter)`
  #
  def index
    if params[:filter] && %w(open processing cancelled completed).include?(params[:filter])
      if params[:user_id]
        @orders = paginate Order.where(status: params[:filter]).order(created_at: :desc)
      else
        @orders = paginate Order.where(user_id: params[:user_id], status: params[:filter]).order(created_at: :desc)
      end
    else
      if params[:user_id]
        @orders = paginate Order.where(user_id: params[:user_id]).order(created_at: :desc)
      else
        @orders = paginate Order.all.order(created_at: :desc)
      end
    end
    respond_to :json, :xml
  end

  def show
    respond_to :json, :xml
  end

  def update
    return api_obj_error(@order.errors.full_messages) unless @order.update(order_params)
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  def destroy
    return api_obj_error(@order.errors.full_messages) unless @order.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def order_params
    params.require(:order).permit(:status, :user_id)
  end

  def find_order
    if params[:find_by_external_id]
      @order = Order.find_by(external_id: params[:id])
    else
      @order = Order.find_by(id: params[:id])
    end
    return api_obj_missing if @order.nil?
    @order.current_user = current_user
  end

end
