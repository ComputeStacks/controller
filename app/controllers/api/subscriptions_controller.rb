##
# Subscriptions API
class Api::SubscriptionsController < Api::ApplicationController

  before_action -> { doorkeeper_authorize! :profile_read }, unless: :current_user

  before_action :load_subscription, only: %w(show)

  ##
  # List all your subscriptions
  #
  # `GET /api/subscriptions`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # You can also view a subscription by passing it's `external_id` as the `id`, and adding the query param `?find_by_external_id=true` to your request.
  #
  # * `subscriptions`: Array
  #     * `id`: Integer
  #     * `label`: String
  #     * `external_id`: String
  #     * `active`: Boolean
  #     * `run_rate`: Decimal
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `subscription_products`: Array
  #         * `id`: Integer
  #         * `external_id`: String
  #         * `start_on`: DateTime
  #         * `active`: Boolean
  #         * `phase_type`: String
  #         * `created_at`: DateTime
  #         * `updated_at`: DateTime
  #         * `product`: Object
  #             * `id`: Integer
  #             * `label`: String
  #             * `kind`: String
  #             * `resource_kind`: String
  #             * `created_at`: DateTime
  #             * `updated_at`: DateTime
  #             * `package`: Object
  #                 * `id`: Integer
  #                 * `cpu`: Decimal
  #                 * `memory`: Integer
  #                 * `storage`: Integer
  #                 * `bandwidth`: Integer
  #                 * `local_disk`: Integer
  #                 * `memory_swap`: Integer
  #                 * `memory_swappiness`: Integer
  #             * `billing_resource`: Object
  #                 * `id`: Integer
  #                 * `billing_plan_id`: Integer
  #                 * `external_id`: String
  #         * `container`: Object
  #             * `id`: Integer
  #             * `name`: String
  #             * `label`: String
  #             * `load_balancer_id`: Integer
  #             * `status`: String
  #             * `cpu`: Decimal
  #             * `memory`: Integer
  #             * `created_at`: DateTime
  #             * `updated_at`: DateTime
  #             * `container_image`: Object
  #                 * `id`: Integer
  #                 * `label`: String
  #                 * `description`: String
  #                 * `image_url`: String
  #             * `deployment`: Object
  #                 * `id`: Integer
  #                 * `name`: String
  #                 * `status`: String
  #                 * `created_at`: DateTime
  #                 * `updated_at`: DateTime
  #             * `service`: Object
  #                 * `id`: Integer
  #                 * `name`: String
  #                 * `label`: String
  #                 * `created_at`: DateTime
  #                 * `updated_at`: DateTime
  #             * `region`: Object
  #                 * `id`: Integer
  #                 * `name`: String
  #             * `node`: Object
  #                 * `id`: Integer
  #                 * `label`: String
  #                 * `hostname`: String
  #                 * `primary_ip`: String
  #                 * `public_ip`: String
  #         * `user`: Object
  #             * `id`: Integer
  #             * `full_name`: String
  #             * `email`: String
  #             * `external_id`: String

  def index
    @subscriptions = if %w(active inactive).include? params[:filter]
                       paginate current_user.subscriptions.where(active: params[:filter] == 'active').sorted
                     else
                       paginate current_user.subscriptions.sorted
                     end
  end

  ##
  # View a subscription
  #
  # `GET /api/subscriptions/{id}`
  #
  # **OAuth AuthorizationRequired**: `profile_read`
  #
  # @see Api::SubscriptionsController#index

  def show; end

  private

  def load_subscription
    if params[:find_by_external_id]
      @subscription = current_user.subscriptions.find_by(external_id: params[:id])
    else
      @subscription = current_user.subscriptions.find_by(id: params[:id])
    end
    return api_obj_missing if @subscription.nil?
  end

end
