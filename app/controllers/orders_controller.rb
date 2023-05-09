class OrdersController < AuthController

  before_action :find_order, except: %i[index new]
  before_action :load_order_session, only: %i[show update destroy]

  def index
    redirect_to "/deployments"
  end

  def new
    redirect_to "/deployments/orders"
  end

  def show
    if request.xhr?
      render template: "orders/order_state", layout: false
    else
      if @order.success? && @order.provision_event&.success? && @order.deployment
        redirect_to "/deployments/#{@order.deployment.token}"
      elsif @order.cancelled?
        redirect_to "/deployments"
      end
    end
  end

  # Process an order
  def update
    if defined?(@order_session)
      session.delete(:deployment_order)
      @order_session.destroy
    end

    # Only allow 'open' orders to be submitted.
    if @order.processing?
      redirect_to "/deployments", notice: "Order has already been submitted."
      return false
    end

    if @order.can_process?
      audit = @order.audits.create!(
        user: current_user,
        ip_addr: request.remote_ip,
        event: 'updated'
      )
      ProcessOrderWorker.perform_async @order.global_id, audit.global_id
    end
    redirect_to @redirect_path
  end

  # Cancel an order
  def destroy
    @order.cancel!
    if defined?(@order_session)
      session.delete(:deployment_order)
      @order_session.destroy
    end
    redirect_to @redirect_path
  end

  private

  def find_order
    @order = current_user.orders.find_by(id: params[:id])
    return(redirect_to("/deployments")) if @order.nil?
    @order.current_user = current_user
    @redirect_path = @order.deployment ? "/deployments/#{@order.deployment.token}" : "/orders/#{@order.id}"
  end

  def load_order_session
    if session[:deployment_order].blank? || session[:deployment_order].is_a?(Hash)
      session.delete(:deployment_order)
    else
      order_session = OrderSession.new(current_user, session[:deployment_order])
      if order_session.location.nil?
        session.delete(:deployment_order)
      else
        @order_session = order_session
      end
    end
  end

end
