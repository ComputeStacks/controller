class Admin::OrdersController < Admin::ApplicationController

  before_action :load_order, except: [:index]

  def index
    orders = Order
    orders = case params[:user].to_i
             when 0
               orders
             else
               @user = User.find_by(id: params[:user])
               @user ? orders.where(user: @user) : orders
             end
    orders = case params[:state]
             when 'completed'
               orders.where(status: 'completed')
             when 'failed'
               orders.where(status: 'failed')
             when 'all'
               orders
             else
               orders.where("status = 'open' OR status = 'processing' OR status = 'awaiting_payment'")
             end
    @orders = orders.sorted.paginate per_page: 25, page: params[:page]
  end

  def show
    begin
      @order_details = @order.order_data.to_yaml
    rescue
      @order_details = "Error loading data."
    end
    if request.xhr?
      render template: 'admin/orders/order', layout: false
      return false
    end
  end

  def process_order
    if @order.can_process?
      audit = @order.audits.create!(
        user: current_user,
        ip_addr: request.remote_ip,
        event: 'created'
      )
      ProcessOrderWorker.perform_async @order.global_id, audit.global_id
      flash[:notice] = "Order will be provisioned shortly."
    else
      flash[:alert] = "Only open orders can be processed."
    end
    redirect_to "/admin/orders/#{@order.id}"
  end

  def destroy
    unless @order.destroy
      flash[:alert] = "Error! #{@order.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/orders"
  end

  private

  def load_order
    @order = Order.find_by(id: params[:id])
    if @order.nil?
      if request.xhr?
        render plain: "Order not found.", layout: false
      else
        redirect_to "/admin/orders", alert: 'Unknown Order.'
      end
      return false
    end
    @order.current_user = current_user
  end

end
