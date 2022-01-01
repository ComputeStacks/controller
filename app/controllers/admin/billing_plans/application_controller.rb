class Admin::BillingPlans::ApplicationController < Admin::ApplicationController
  before_action :load_plan

  private

  def load_plan
    @billing_plan = BillingPlan.find_by(id: params[:billing_plan_id])
    if @billing_plan.nil?
      redirect_to "/admin/billing_plans", alert: 'Unknown Billing Plan.'
      return false
    end
    @billing_plan.current_user = current_user
    @plan_base_url = "/admin/billing_plans/#{@billing_plan.id}"
  end
end
