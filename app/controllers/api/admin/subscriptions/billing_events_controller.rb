class Api::Admin::Subscriptions::BillingEventsController < Api::Admin::Subscriptions::BaseController

  before_action :load_billing_event, except: %i[ index ]

  # GET /admin/(subscriptions/:subscription_id | users/:user_id)/billing_events
  def index
    if @user
      @billing_events = paginate @user.billing_events
    else
      @billing_events = paginate @subscription.billing_events
    end
  end

  def show; end

  private

  def load_billing_event
    @billing_event = BillingEvent.find_by(id: params[:id])
    api_obj_missing(["Unknown Billing Event"]) if @billing_event.nil?
  end

end
