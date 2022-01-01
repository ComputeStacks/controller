class Admin::Subscriptions::BaseController < Admin::ApplicationController

  before_action :find_subscription

  private

  def find_subscription
    @subscription = Subscription.find_by(id: params[:subscription_id])
    if @subscription.nil?
      redirect_to "/admin/subscriptions", alert: 'Unknown Subscription'
      return false
    end
  end

end
