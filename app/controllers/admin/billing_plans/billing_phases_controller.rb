class Admin::BillingPlans::BillingPhasesController < Admin::BillingPlans::ApplicationController

  before_action :load_base_url
  before_action :load_phase, only: [:show, :edit, :update, :destroy]

  def show
    if @phase.prices.empty?
      redirect_to "#{@base_url}/billing_phases/#{@phase.id}/billing_resource_prices/new"
    end
  end

  def new
    resource = @billing_plan.billing_resources.find_by(id: params[:billing_resource_id])
    if resource.nil?
      redirect_to @base_url, alert: 'Unknown Billing Resource'
      return false
    end
    @phase = @billing_plan.billing_phases.new(billing_resource_id: resource.id)
  end

  def edit; end

  def update
    if phase_params[:duration_qty].blank? || phase_params[:duration_qty].to_i == 0
      phase_params[:duration_qty] = nil
    end
    if @phase.update(phase_params)
      redirect_to "#{@base_url}/billing_phases/#{@phase.id}", notice: 'Phase Updated'
      return false
    else
      render template: 'admin/billing_plans/billing_phases/edit'
    end
  end

  def create
    if phase_params[:duration_qty].blank? || phase_params[:duration_qty].to_i == 0
      phase_params.delete(:duration_qty)
    end
    @phase = @billing_plan.billing_phases.new(phase_params)
    @phase.current_user = current_user
    if @phase.save
      redirect_to "#{@base_url}/billing_phases/#{@phase.id}", notice: 'Phase Created'
    else
      render template: 'admin/billing_plans/billing_phases/new'
    end
  end

  def destroy
    if @phase.phase_type == 'final'
      flash[:alert] = 'Unable to delete final phase.'
    elsif @phase.destroy
      flash[:notice] = 'Phase Deleted'
    else
      flash[:alert] = "Unable to delete phase: #{@phase.errors.full_messages.join(' ')}"
    end
    redirect_to @base_url
  end

  private

  def load_base_url
    @base_url = "/admin/billing_plans/#{@billing_plan.id}"
  end

  def phase_params
    params.require(:billing_phase).permit(:duration_unit, :duration_qty, :billing_resource_id, :billing_plan_id, :phase_type)
  end

  def load_phase
    @phase = @billing_plan.billing_phases.find_by(id: params[:id])
    if @phase.nil?
      redirect_to @base_url, alert: 'Unknown Phase'
      return false
    end
    @phase.current_user = current_user
  end

end
