class Admin::BillingPlans::BillingPhases::BillingResourcePricesController < Admin::BillingPlans::ApplicationController

  before_action :load_phase
  before_action :load_price, only: [:show, :edit, :update, :destroy]

  def show
    redirect_to "#{@base_price_url}/edit"
    return false
  end

  def edit
    @regions = Region.all.order(name: :asc)
  end

  def new
    @price = BillingResourcePrice.new
    @price.billing_phase = @phase
    @price.billing_resource = @phase.billing_resource
    @regions = Region.all.order(name: :asc)
  end

  def update
    if params[:unlimited]
      params[:billing_resource_price].delete(:max_qty)
      @price.max_qty = nil
    end
    if @price.update(price_params)
      flash[:notice] = 'Successfully updated price'
      redirect_to @base_url
    else
      @regions = Region.all.order(name: :asc)
      flash[:alert] = "Error! #{@price.errors.full_messages.join(' ')}"
      render template: 'admin/billing_plans/billing_phases/billing_resource_prices/edit'
    end
  end

  def create
    if params[:unlimited]
      params[:billing_resource_price].delete(:max_qty)
    end
    @price = @phase.prices.new(price_params)
    @price.current_user = current_user
    @price.billing_resource = @phase.billing_resource
    if @price.save
      redirect_to @base_url, notice: 'Success!'
    else
      @regions = Region.all.order(name: :asc)
      render template: 'admin/billing_plans/billing_phases/billing_resource_prices/new'
    end
  end

  def destroy
    if @price.destroy
      flash[:notice] = 'Price deleted.'
    else
      flash[:error] = "Error! #{@price.errors.full_messages.join(' ')}"
    end
    redirect_to @base_url
  end

  private

  def price_params
    params.require(:billing_resource_price).permit(:currency, :max_qty, :price, {region_ids: []})
  end

  def load_phase
    @phase = @billing_plan.billing_phases.find_by(id: params[:billing_phase_id])
    if @phase.nil?
      redirect_to "/admin/billing_plans/#{@billing_plan.id}/billing_phases", alert: 'Unknown Phase'
      return false
    end
    @base_url = "/admin/billing_plans/#{@billing_plan.id}/billing_phases/#{@phase.id}"
  end

  def load_price
    @price = @phase.prices.find_by(id: params[:id])
    if @price.nil?
      redirect_to @base_url, alert: 'Unknown Phase'
      return false
    end
    @price.current_user = current_user
    @base_price_url = "#{@base_url}/billing_resource_prices/#{@price.id}"
  end

end
