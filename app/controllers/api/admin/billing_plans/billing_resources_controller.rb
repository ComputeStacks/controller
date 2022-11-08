##
# # Billing Resources
#
class Api::Admin::BillingPlans::BillingResourcesController < Api::Admin::BillingPlans::BaseController

  before_action :find_billing_resource, except: %i[ index create ]

  ##
  # List All Billing Resources
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources`
  #
  # * `billing_resources`: Array
  #     * `id`
  #     * `billing_plan_id`: Integer
  #     * `external_id`: String
  #     * `prorate`: Boolean
  #     * `product_id`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @billing_resources = paginate @billing_plan.billing_resources
    respond_to :json, :xml
  end

  ##
  # View Billing Resource
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources/{id}`
  #
  # * `billing_resource`: Object
  #     * `id`
  #     * `billing_plan_id`: Integer
  #     * `external_id`: String
  #     * `prorate`: Boolean
  #     * `product_id`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show
    respond_to :json, :xml
  end

  ##
  # Edit Billing Resource
  #
  # `PATCH /api/admin/billing_plans/{billing_plan_id}/billing_resources/{id}`
  #
  # * `billing_resource`: Object
  #     * `billing_plan_id`: Integer
  #     * `external_id`: String
  #     * `product_id`: Integer
  #     * `prorate`: Boolean
  #
  def update
    return api_obj_error(@billing_resource.errors.full_messages) unless @billing_resource.update(resource_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Billing Resource
  #
  # `POST /api/admin/billing_plans/{billing_plan_id}/billing_resources`
  #
  # * `billing_resource`: Object
  #     * `external_id`: String
  #     * `product_id`: Integer
  #     * `prorate`: Boolean
  def create
    @billing_resource = @billing_plan.billing_resources.new(resource_params)
    @billing_resource.current_user = current_user
    return api_obj_error(@billing_resource.errors.full_messages) unless @billing_resource.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Billing Resource
  #
  # `DELETE /api/admin/billing_plans/{billing_plan_id}/billing_resources/{id}`

  def destroy
    return api_obj_error(@billing_resource.errors.full_messages) unless @billing_resource.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :ok }
    end
  end

  private

  def resource_params
    params.require(:billing_resource).permit(:product_id, :external_id, :prorate)
  end

  def find_billing_resource
    @billing_resource = @billing_plan.billing_resources.find_by(id: params[:id])
    return api_obj_missing if @billing_resource.nil?
  end

end
