##
# # Billing Usage
#
class Api::Admin::Subscriptions::BillingUsagesController < Api::Admin::Subscriptions::BaseController

  before_action :load_usage, except: %i[ index ]

  ##
  # List Usage for a subscription
  #
  # `GET /admin/subscriptions/{subscription_id}/billing_usages`
  # `GET /admin/users/{user_id)/billing_usages`
  #
  # * `billing_usages`: Array
  #     * `id`: Integer
  #     * `period_start`: DateTime
  #     * `period_end`: DateTime
  #     * `external_id`: String
  #     * `rate`: Decimal
  #     * `qty`: Decimal - Billable QTY (less what would be included in their package)
  #     * `qty_total`: Decimal - Total QTY recorded
  #     * `total`: Decimal
  #     * `processed`: Boolean
  #     * `processed_on`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `subscription_product`: Object
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
  #             * `resource_kind`
  #             * `unit`: String
  #             * `unit_type`: String
  #             * `external_id`: DateTime
  #             * `package`: Object
  #                 * `id`: Integer
  #                 * `cpu`: Decimal
  #                 * `memory`: Integer
  #                 * `storage`: Integer
  #                 * `bandwidth`: Integer
  #                 * `local_disk`: Integer
  #                 * `memory_swap`: Integer
  #                 * `memory_swappiness`: Integer
  #                 * `backup`: Integer
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`: String
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object

  def index
    if @user
      @usages = paginate @user.billing_usages
    else
      @usages = paginate @subscription.billing_usages
    end
    respond_to :json, :xml
  end

  ##
  # View Usage Item
  #
  # `GET /admin/subscriptions/{subscription_id}/billing_usages/{id}`
  #
  # * `billing_usages`: Object
  #     * `id`: Integer
  #     * `period_start`: DateTime
  #     * `period_end`: DateTime
  #     * `external_id`: String
  #     * `rate`: Decimal
  #     * `qty`: Decimal - Billable QTY (less what would be included in their package)
  #     * `qty_total`: Decimal - Total QTY recorded
  #     * `total`: Decimal
  #     * `processed`: Boolean
  #     * `processed_on`: DateTime
  #     * `created_at`: DateTime
  #     * `updated_at`: DateTime
  #     * `subscription_product`: Object
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
  #             * `resource_kind`
  #             * `unit`: String
  #             * `unit_type`: String
  #             * `external_id`: DateTime
  #             * `package`: Object
  #                 * `id`: Integer
  #                 * `cpu`: Decimal
  #                 * `memory`: Integer
  #                 * `storage`: Integer
  #                 * `bandwidth`: Integer
  #                 * `local_disk`: Integer
  #                 * `memory_swap`: Integer
  #                 * `memory_swappiness`: Integer
  #                 * `backup`: Integer
  #     * `user`: Object
  #         * `id`: Integer
  #         * `full_name`
  #         * `email`: String
  #         * `external_id`: String
  #         * `labels`: Object

  def show
    respond_to :json, :xml
  end

  ##
  # Delete a usage item
  #
  # `DELETE /admin/subscriptions/{subscription_id}/billing_usages/{id}`

  def destroy
    return api_obj_error(@usage.errors.full_messages) unless @usage.destroy
    respond_to do |f|
      f.any(:json, :xml) { head :no_content }
    end
  end

  private

  def load_usage
    @usage = BillingUsage.find_by(id: params[:id])
    api_obj_missing(["Unknown Usage."]) if @usage.nil?
  end

end
