class Api::Admin::BillingPlans::BaseController < Api::Admin::ApplicationController

  before_action :load_billing_plan

  private

  def load_billing_plan
    @billing_plan = BillingPlan.find_by(id: params[:billing_plan_id])
    return api_obj_missing if @billing_plan.nil?
    @billing_plan.current_user = current_user
  end

end
