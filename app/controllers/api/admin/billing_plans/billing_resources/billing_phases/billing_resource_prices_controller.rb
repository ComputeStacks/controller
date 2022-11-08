##
# Billing Resource Price
class Api::Admin::BillingPlans::BillingResources::BillingPhases::BillingResourcePricesController < Api::Admin::BillingPlans::BaseController

  before_action :find_parents
  before_action :find_price, except: %i[ index create ]

  ##
  # List All Prices
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{billing_phase_id}/billing_resource_prices`
  #
  # * `billing_resource_prices`: Array
  #     * `id`: Integer
  #     * `billing_phase_id`: Integer
  #     * `billing_resource_id`: Integer
  #     * `currency`: String
  #     * `max_qty`: Decimal
  #     * `price`: Decimal
  #     * `term`: String | hour,month
  #     * `regions`: Array
  #         * `id`: Integer
  #         * `name`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def index
    @prices = paginate @billing_phase.prices.sorted
    respond_to :json, :xml
  end

  ##
  # View Price
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{billing_phase_id}/billing_resource_prices/{id}`
  #
  # * `billing_resource_price`: Object
  #     * `id`: Integer
  #     * `billing_phase_id`: Integer
  #     * `billing_resource_id`: Integer
  #     * `currency`: String
  #     * `max_qty`: Decimal
  #     * `price`: Decimal
  #     * `term`: String | hour,month
  #     * `regions`: Array
  #         * `id`: Integer
  #         * `name`: String
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #
  def show
    respond_to :json, :xml
  end

  ##
  # Update Price
  #
  # `PATCH /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{billing_phase_id}/billing_resource_prices/{id}`
  #
  # * `billing_resource_price`: Object
  #     * `currency`: String
  #     * `max_qty`: Decimal
  #     * `price`: Decimal
  #     * `region_ids`: Array<Integer>

  def update
    if params.dig('billing_resource_price', 'max_qty').blank?
      params[:billing_resource_price].delete(:max_qty)
      @price.max_qty = nil
    end
    return api_obj_error(@price.errors.full_messages) unless @price.update(price_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Price
  #
  # `POST /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{billing_phase_id}/billing_resource_prices`
  #
  # * `billing_resource_price`: Object
  #     * `currency`: String
  #     * `max_qty`: Decimal
  #     * `price`: Decimal
  #     * `region_ids`: Array<Integer>

  def create
    if params.dig('billing_resource_price', 'max_qty').blank?
      params[:billing_resource_price].delete(:max_qty)
    end
    @price = @billing_phase.prices.new(price_params)
    @price.current_user = current_user
    @price.billing_resource = @billing_phase.billing_resource
    return api_obj_error(@price.errors.full_messages) unless @price.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Price
  #
  # `DELETE /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{billing_phase_id}/billing_resource_prices/{id}`

  def destroy
    return api_obj_error(@price.errors.full_messages) unless @price.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :ok }
    end
  end

  private

  def find_parents
    @billing_resource = @billing_plan.billing_resources.find_by(id: params[:billing_resource_id])
    return api_obj_missing if @billing_resource.nil?
    @billing_phase = @billing_resource.billing_phases.find_by(id: params[:billing_phase_id])
    return api_obj_missing if @billing_phase.nil?
  end

  def find_price
    @price = @billing_phase.prices.find_by(id: params[:id])
    return api_obj_missing if @price.nil?
  end

  def price_params
    params.require(:billing_resource_price).permit(:currency, :max_qty, :price, {region_ids: []})
  end



end
