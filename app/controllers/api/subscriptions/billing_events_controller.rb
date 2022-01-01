##
# Billing Events API
class Api::Subscriptions::BillingEventsController < Api::Subscriptions::BaseController

  before_action :load_billing_event, except: %i[ index ]

  ##
  # List Events
  #
  # `GET /api/subscriptions/{subscription-id}/billing_events`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # * `billing_events`: Array
  #     * `id`: Integer
  #     * `from_status`: Boolean
  #     * `to_status`: Boolean
  #     * `from_phase`: String<trial,discount,final>
  #     * `to_phase`: String<trial,discount,final>
  #     * `from_resource_qty`: Integer
  #     * `to_resource_qty`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `subscription`: Object<Subscription>
  #     * `source_product`: Object<Product>
  #     * `destination_product`: Object<Product>
  #
  def index
    @billing_events = paginate @subscription.billing_events
  end

  ##
  # View Event
  #
  # `GET /api/subscriptions/{subscription-id}/billing_events/{id}`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # * `billing_event`: Object
  #     * `id`: Integer
  #     * `from_status`: Boolean
  #     * `to_status`: Boolean
  #     * `from_phase`: String<trial,discount,final>
  #     * `to_phase`: String<trial,discount,final>
  #     * `from_resource_qty`: Integer
  #     * `to_resource_qty`: Integer
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `subscription`: Object<Subscription>
  #     * `source_product`: Object<Product>
  #     * `destination_product`: Object<Product>
  #
  def show; end

  private

  def load_billing_event
    @billing_event = current_user.billing_events.find_by(id: params[:id])
    api_obj_missing(["Unknown Billing Event"]) if @billing_event.nil?
  end

end
