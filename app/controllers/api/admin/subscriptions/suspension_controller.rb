##
# # Suspend a subscription
class Api::Admin::Subscriptions::SuspensionController < Api::Admin::Subscriptions::BaseController

  before_action :ensure_user_exists

  ##
  # Suspend a subscription
  #
  # `POST /api/admin/subscriptions/{subscription_id}/suspension`
  #
  def create
    @subscription.user.update active: false
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  ##
  # Activate a subscription
  #
  # `DELETE /api/admin/subscriptions/{subscription_id}/suspension`
  #
  def destroy
    @subscription.user.update active: true
    respond_to do |f|
      f.json { render json: {}, status: :accepted }
      f.xml { render xml: {}, status: :accepted }
    end
  end

  private

  def ensure_user_exists
    return api_obj_error(['Unknown User']) if @subscription.user.nil?
    return api_obj_error(['Unknown User']) if @subscription.user.is_support_admin?
  end

end
