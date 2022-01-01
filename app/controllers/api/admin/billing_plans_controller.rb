##
# Billing Plan
class Api::Admin::BillingPlansController < Api::Admin::ApplicationController

  before_action :load_billing_plan, except: %i[ index create ]

  ##
  # List All Billing Plans
  #
  # `GET /api/admin/billing_plans`
  #
  # * `billing_plans`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `user_groups`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @billing_plans = paginate BillingPlan.all.order(:created_at)
    respond_to :json, :xml
  end

  ##
  # View Billing Plan
  #
  # `GET /api/admin/billing_plans/{id}`
  #
  # * `billing_plans`: Array
  #     * `id`: Integer
  #     * `name`: String
  #     * `user_groups`: Array
  #         * `id`: Integer
  #         * `name`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `billing_resources`: Array
  #         * `id`: Integer
  #         * `external_id`: String
  #         * `product`: Object
  #             * `id`: Integer
  #             * `label`: String
  #             * `resource_kind`: String - package, resource
  #             * `unit`: Integer
  #             * `unit_type`: String - GB, MB, Core, etc...
  #             * `external_id`: String
  #             * `package`: Object
  #                 * `id`: Integer
  #                 * `cpu`: Number
  #                 * `memory`: Integer
  #                 * `storage`: Integer
  #                 * `bandwidth`: Integer
  #                 * `local_disk`: Integer
  #                 * `memory_swap`: Integer
  #                 * `memory_swappiness`: Integer
  #                 * `backup`: Integer
  #         * `billing_phases`: Array
  #             * `id`: Integer
  #             * `phase_type`: String - trial, discount, or final
  #             * `duration_unit`: for trial, discount only - hours, days, months, years
  #             * `duration_qty`: for trial, discount only - how many units of duration_unit.
  #             * `billing_resource_prices`: Array
  #                 * `id`: Integer
  #                 * `currency`: String - 3-letter currency (USD, EUR)
  #                 * `max_qty`: Number - set to `null` for unlimited. Otherwise, this is the max qty for the price. (used with tiered pricing)
  #                 * `price`: Number
  #                 * `regions`: Array
  #                     * `id`: Integer
  #                     * `name`: String

  def show
    respond_to :json, :xml
  end

  ##
  # Create Billing Plan
  #
  # `POST /api/admin/billing_plans`
  #
  # * `billing_plan`
  #     * `name`: String
  #     * `user_group_ids`: Array - optionally link to user groups.
  #     * `clone`: Integer - the ID of another billing plan to clone

  def create
    @billing_plan = BillingPlan.new(name: billing_plan_params[:name])
    @billing_plan.current_user = current_user
    @billing_plan.clone = BillingPlan.find_by(id: billing_plan_params[:clone]) if billing_plan_params[:clone]
    if billing_plan_params[:user_group_ids]
      billing_plan_params[:user_group_ids].each do |g|
        ug = UserGroup.find_by(id: g)
        @billing_plan.user_groups << ug if ug
      end
    end
    return api_obj_error(@billing_plan.errors.full_messages) unless @billing_plan.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Update Billing Plan
  #
  # `PATCH /api/admin/billing_plans/{id}`
  #
  # * `billing_plan`
  #     * `name`: String
  #     * `user_group_ids`: Array - Omit this field if you do not want to change existing values.

  def update
    if billing_plan_params[:user_group_ids] && !billing_plan_params[:user_group_ids].empty?
      @billing_plan.user_groups = []
      billing_plan_params[:user_group_ids].each do |g|
        ug = UserGroup.find_by(id: g)
        @billing_plan.user_groups << ug if ug
      end
    end
    @billing_plan.name = billing_plan_params[:name]
    return api_obj_error(@billing_plan.errors.full_messages) unless @billing_plan.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Destroy Billing Plan
  #
  # `DELETE /api/admin/billing_plans/{id}`
  #
  # This will fail if this is currently assigned to any user groups.

  def destroy
    return api_obj_error(@billing_plan.errors.full_messages) unless @billing_plan.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :no_content }
    end
  end

  private

  def billing_plan_params
    params.require(:billing_plan).permit(:name, :user_group_ids, :clone)
  end

  def load_billing_plan
    @billing_plan = BillingPlan.find_by(id: params[:id])
    return api_obj_missing if @billing_plan.nil?
    @billing_plan.current_user = current_user
  end

end
