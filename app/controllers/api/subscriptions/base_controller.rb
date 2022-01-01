class Api::Subscriptions::BaseController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, unless: :current_user

  before_action :load_parent

  private

  def load_parent
    if params[:find_by_external_id]
      @subscription = current_user.subscriptions.find_by(external_id: params[:subscription_id])
    else
      @subscription = current_user.subscriptions.find_by(id: params[:subscription_id])
    end
    api_obj_missing(["Unknown Subscription"]) if @subscription.nil?
  end

end