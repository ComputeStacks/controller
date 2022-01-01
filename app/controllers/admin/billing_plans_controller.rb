class Admin::BillingPlansController < Admin::ApplicationController

  before_action :load_plan, only: [:show, :edit, :update, :destroy]

  def index
    @billing_plans = BillingPlan.order(:name)
  end

  def new
    @billing_plan = BillingPlan.new
    if params[:clone]
      orig = BillingPlan.find_by(id: params[:clone])
      if orig
        @billing_plan.name = "#{orig.name} (copy)"
        @billing_plan.clone = orig
      end
    end
  end

  def show
    @packages = @billing_plan.billing_resources.joins(:product).where(Arel.sql(%Q(products.kind = 'package'))).order( Arel.sql(%Q(lower(products.label))) )
    @products = @billing_plan.billing_resources.joins(:product).where(Arel.sql(%Q(products.kind != 'package'))).order( Arel.sql(%Q(lower(products.label))) )
  end

  def edit

  end

  def update
    @billing_plan.current_user = current_user
    if @billing_plan.update(plan_params)
      flash[:success] = "Plan Update"
    else
      flash[:alert] = "Error! #{@billing_plan.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/billing_plans/#{@billing_plan.id}"
  end

  def create
    @billing_plan = BillingPlan.new(name: plan_params[:name])
    @billing_plan.clone = BillingPlan.find_by(id: plan_params[:clone]) if plan_params[:clone]
    @billing_plan.current_user = current_user
    if @billing_plan.save
      flash[:success] = "Plan Created"
    else
      flash[:alert] = "Error! #{@billing_plan.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/billing_plans/#{@billing_plan.id}"
  end

  def destroy
    @billing_plan.current_user = current_user
    if @billing_plan.destroy
      flash[:success] = "Plan Deleted"
    else
      flash[:alert] = "Error! #{@billing_plan.errors.full_messages.join(' ')}"
    end
    redirect_to "/admin/billing_plans"
  end

  private

  def plan_params
    params.require(:billing_plan).permit(:name, :clone)
  end

  def load_plan
    @billing_plan = BillingPlan.find_by(id: params[:id])
    if @billing_plan.nil?
      redirect_to "/admin/billing_plans", alert: 'Unknown Billing Plan.'
      return false
    end
    @base_url = "/admin/billing_plans/#{@billing_plan.id}"
  end

end
