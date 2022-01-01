class Admin::BillingPlans::BillingResourcesController < Admin::BillingPlans::ApplicationController

  before_action :load_resource, only: [:edit, :update, :destroy]

  def new
    @billing_resource = @billing_plan.billing_resources.new
  end

  def edit; end

  def show
    redirect_to action: :edit
  end

  def update
    if @billing_resource.update(resource_params)
      redirect_to @plan_base_url, notice: "Successfully updated."
    else
      render template: 'admin/billing_plans/billing_resources/edit'
    end
  end

  def create
    @billing_resource = @billing_plan.billing_resources.new(resource_params)
    @billing_resource.current_user = current_user
    if @billing_resource.save
      redirect_to @plan_base_url, notice: "Successfully added resource."
    else
      render template: 'admin/billing_plans/billing_resources/new'
    end
  end

  def destroy
    if @billing_resource.destroy
      flash[:notice] = 'Resource removed from billing plan.'
    else
      flash[:alert] = 'Error deleting resource!'
    end
    redirect_to @plan_base_url
  end

  private

  def resource_params
    params.require(:billing_resource).permit(:product_id, :external_id, :val_min, :val_max, :val_default, :val_step, {template_ids: []})
  end

  def load_resource
    @billing_resource = @billing_plan.billing_resources.find_by(id: params[:id])
    if @billing_resource.nil?
      redirect_to "/admin/billing_plans/#{@billing_plan.id}", alert: 'Unknown Resource'
      return false
    end
    @billing_resource.current_user = current_user
  end

end
