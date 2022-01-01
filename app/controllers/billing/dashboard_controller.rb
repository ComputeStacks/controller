# WIP
class Billing::DashboardController < AuthController

  def index
    @monthly_summary = current_user.usage_by_month
    @product_summary = current_user.product_usage_by_month
    # respond_to do |format|
    #   format.html { }
    #   format.json { render json: @service.metric_mem_usage(3.hours.ago, Time.now).map { |i| {name: i[0], data: i[1]}} }
    # end
  end


end
