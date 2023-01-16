class Api::Admin::Orders::ProcessOrderController < Api::Admin::ApplicationController

  before_action :load_order

  ##
  # =Process an order
  #
  # Billing integrations expect a 200x for all calls.
  #
  def create
    audit = @order.audits.create!(
      user: current_user,
      ip_addr: request.remote_ip,
      event: 'updated'
    )
    ProcessOrderWorker.perform_async @order.global_id, @audit.global_id
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  private

  def load_order
    if params[:find_by_external_id]
      @order = Order.find_by(external_id: params[:order_id])
    else
      @order = Order.find_by(id: params[:order_id])
    end
    api_obj_missing(["Unknown order."]) if @order.nil?
  end

end
