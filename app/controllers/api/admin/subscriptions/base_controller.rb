class Api::Admin::Subscriptions::BaseController < Api::Admin::ApplicationController

  before_action :load_parent

  private

  def load_parent
    if params[:user_id]
      @user = User.find_by(id: params[:user_id])
      api_obj_missing(["Unknown User"]) if @user.nil?
    else
      if params[:find_by_external_id]
        @subscription = Subscription.find_by(external_id: params[:subscription_id])
      else
        @subscription = Subscription.find_by(id: params[:subscription_id])
      end
      api_obj_missing(["Unknown Subscription"]) if @subscription.nil?
    end
  end

end