##
# Billing Phases
class Api::Admin::BillingPlans::BillingResources::BillingPhasesController < Api::Admin::BillingPlans::BaseController

  before_action :find_billing_resource
  before_action :find_billing_phase, except: %i[ index create ]

  ##
  # List All Billing Phases
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases`
  #
  # * `billing_phases`: Array
  #     * `id`: Integer
  #     * `billing_resource_id`: Integer
  #     * `phase_type`: String
  #     * `duration_unit`: String
  #     * `duration_qty`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def index
    @billing_phases = @billing_resource.billing_phases.order(:id)
    respond_to :json, :xml
  end

  ##
  # View Billing Phase
  #
  # `GET /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{id}`
  #
  # * `billing_phase`: Object
  #     * `id`: Integer
  #     * `billing_resource_id`: Integer
  #     * `phase_type`: String
  #     * `duration_unit`: String
  #     * `duration_qty`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime

  def show
    respond_to :json, :xml
  end

  ##
  # Update Billing Phase
  #
  # `PATCH /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{id}`
  #
  # * `billing_phase`: Object
  #     * `phase_type`: String
  #     * `duration_unit`: String
  #     * `duration_qty`: Integer

  def update
    if phase_params[:duration_qty].blank? || phase_params[:duration_qty].to_i == 0
      phase_params[:duration_qty] = nil
    end
    return api_obj_error(@phase.errors.full_messages) unless @phase.update(phase_params)
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :ok }
    end
  end

  ##
  # Create Billing Phase
  #
  # `POST /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases`
  #
  # * `billing_phase`: Object
  #     * `phase_type`: String
  #     * `duration_unit`: String
  #     * `duration_qty`: Integer

  def create
    if phase_params[:duration_qty].blank? || phase_params[:duration_qty].to_i == 0
      phase_params.delete(:duration_qty)
    end
    @phase = @billing_plan.billing_phases.new(phase_params)
    @phase.current_user = current_user
    return api_obj_error(@phase.errors.full_messages) unless @phase.save
    respond_to do |format|
      format.any(:json, :xml) { render action: :show, status: :created }
    end
  end

  ##
  # Delete Billing Phase
  #
  # `DELETE /api/admin/billing_plans/{billing_plan_id}/billing_resources/{billing_resource_id}/billing_phases/{id}`

  def destroy
    return api_obj_error(@phase.errors.full_messages) unless @phase.destroy
    respond_to do |format|
      format.any(:json, :xml) { head :ok }
    end
  end

  private

  def phase_params
    params.require(:billing_phase).permit(:duration_unit, :duration_qty, :phase_type)
  end

  def find_billing_resource
    @billing_resource = @billing_plan.billing_resources.find_by(id: params[:billing_resource_id])
    return api_obj_missing if @billing_resource.nil?
  end

  def find_billing_phase
    @phase = @billing_resource.billing_phases.find_by(id: params[:id])
    return api_obj_missing if @phase.nil?
  end



end
