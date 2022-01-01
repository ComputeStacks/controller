##
# BillingResource
#
# Parent object for:
#   * Price
#   * Phase
#   * BillingPlan
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute billing_plan
#   @return [BillingPlan]
#
# @!attribute product
#   @return [Product]
#
# @!attribute external_id
#   @return [String] used by third-party integrations
#
# @!attribute val_min
#   @return [Decimal]
#
# @!attribute val_max
#   @return [Decimal]
#
# @!attribute val_step
#   @return [Decimal] For sliders
#
# @!attribute val_default
#   @return [Decimal]
#
class BillingResource < ApplicationRecord

  #
  # FOR VALUES: actual_value = val_X * product.val_unit
  # val_min:decimal # Min. for order
  # val_max:decimal # Max. for order
  # val_default:decimal # Default val for order
  # val_step:decimal # For sliders.
  #
  # NOTES:
  #  - Dynamically find the billing_resource by looking at the billing_plan of the user, and this product id.
  #

  include Auditable

  has_many :prices, class_name: 'BillingResourcePrice'
  belongs_to :product, optional: true
  belongs_to :billing_plan, optional: true
  has_many :billing_phases, dependent: :destroy
  has_one :package, through: :product

  validates :product_id, presence: true

  attr_accessor :skip_default_phase
  after_create :create_default_phase, unless: :skip_default_phase

  ## Create an array of phases
  # Used to force the order we want.
  def available_phases
    p = []
    trial_phase = billing_phases.find_by(phase_type: 'trial')
    discount_phase = billing_phases.find_by(phase_type: 'discount')
    final_phase = billing_phases.find_by(phase_type: 'final')
    p << trial_phase if trial_phase
    p << discount_phase if discount_phase
    p << final_phase
    p
  end

  ##
  # Determine subscription phase
  #  - subscription_product = SubscriptionProduct
  #  - new_user_check = Boolean
  #
  # Returns: BillingPhase
  def determine_phase(subscription_product)
    trial_phase = billing_phases.find_by(phase_type: 'trial')
    discount_phase = billing_phases.find_by(phase_type: 'discount')
    user = subscription_product.subscription.user
    if trial_phase && trial_phase.in_phase?(user)
      'trial'
    elsif discount_phase && discount_phase.in_phase?(user)
      'discount'
    else
      'final'
    end
  end

  private

  def create_default_phase
    return if billing_phases.where(phase_type: 'final').exists?
    billing_phases.create!(phase_type: 'final')
  end

end
