class Api::Admin::Subscriptions::BillingEventsController < Api::Admin::Subscriptions::BaseController
  before_action :load_billing_event, except: %i[index]

  # GET /admin/(subscriptions/:subscription_id | users/:user_id)/billing_events
  def index
    @billing_events = if @user
      paginate @user.billing_events
    else
      paginate @subscription.billing_events
    end
  end

  def show
  end

  private

  def load_billing_event
    @billing_event = BillingEvent.find_by(id: params[:id])
    api_obj_missing(["Unknown Billing Event"]) if @billing_event.nil?
  end
end
