class Api::Subscriptions::BaseController < Api::ApplicationController
  api_scope read: :profile_read

  before_action :load_parent

  private

  def load_parent
    @subscription = if params[:find_by_external_id]
      current_user.subscriptions.find_by(external_id: params[:subscription_id])
    else
      current_user.subscriptions.find_by(id: params[:subscription_id])
    end
    api_obj_missing(["Unknown Subscription"]) if @subscription.nil?
  end
end
