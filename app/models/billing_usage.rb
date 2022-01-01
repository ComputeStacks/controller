##
# BillingUsage
#
# Stores consumed resources for later processing.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute period_start
#   @return [DateTime]
#
# @!attribute period_end
#   @return [DateTime]
#
# @!attribute external_id
#   @return [String] Used by third-party integrations
#
# @!attribute rate
#   @return [Decimal]
#
# @!attribute qty
#   @return [Decimal]
#
# @!attribute qty_total
#   @return [Decimal]
#
# @!attribute total
#   @return [Decimal]
#
# @!attribute processed
#   @return [Boolean]
#
# @!attribute processed_on
#   @return [DateTime]
#
# @!attribute user
#   @return [User]
#
# @!attribute product
#   @return [Product]
#
#
# * For packages, rate & total will be 0.00.
#   + Any amount over 0.00 will be their overage usage.
# * Will not create items for services without a product.
# * For overage billing (storage, bandwidth):
# * The qty will be what's in excess of their included amount. Not the total amount.
#
class BillingUsage < ApplicationRecord

  default_scope { order(created_at: :desc) }

  belongs_to :user, optional: true

  belongs_to :subscription_product, optional: true
  has_one :product, through: :subscription_product
  has_one :subscription, through: :subscription_product

  ##
  # Determine the hourly rate (Display Only)
  # This is not used in any actual billing calculations.
  # This is used to help calculate the current estimated monthly cost for this service
  def hourly_run_rate
    return 0e0 if total.zero?
    return rate if product&.is_aggregated
    # For consumables, the rate is per-unit. We need to convert that to per-hour.
    period_length = ((period_end - period_start).to_f / 1.hour).round(4)
    (total / period_length).round(8)
  end

end
