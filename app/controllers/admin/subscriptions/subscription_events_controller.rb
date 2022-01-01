class Admin::Subscriptions::SubscriptionEventsController < Admin::Subscriptions::BaseController

  before_action :load_event, except: :index

  def index
    @events = @subscription.billing_events.paginate per_page: 25, page: params[:page]
  end

  def show

  end

  private

  def load_event
    @event = @subscription.billing_events.find_by(id: params[:id])
    if @event.nil?
      redirect_to "/admin/subscriptions/#{@subscription.id}/subscription_events"
      return falseApplicationControllerApplicationController
    end
  end

end
