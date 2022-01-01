##
# Subscription Product
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute external_id
#   Used by third party billing systems and integrations.
#   @return [String]
#
# @!attribute phase_type
#   @return [trial,discount,final]
#
# @!attribute product
#   @return [Product]
#
# @!attribute subscription
#   @return [Subscription]
#
# @!attribute billing_resource
#   @return [BillingResource]
#
# @!attribute billing_usages
#   @return [Array<BillingUsage>]
#
# @!attribute billing_events
#   @return [Array<BillingEvent>]
#
# @!attribute price_resources
#   @return [Array<BilingResourcePrice>]
#
# @!attribute phase_resources
#   @return [Array<BillingPhase>]
#
class SubscriptionProduct < ApplicationRecord

  include Auditable

  belongs_to :subscription, optional: true

  has_one :user, through: :subscription
  has_one :billing_plan, through: :user

  has_one :billing_resource, ->(sb) { where product: sb.product }, through: :billing_plan, source: :billing_resources
  has_many :price_resources, through: :billing_resource, source: :prices
  has_many :phase_resources, through: :billing_resource, source: :billing_phases

  belongs_to :product, optional: true
  has_one :package, through: :product
  has_many :billing_usages, dependent: :destroy
  has_many :billing_events, dependent: :destroy

  validates :phase_type, inclusion: {in: %w(trial discount final)}, unless: :allow_nil_phase

  attr_accessor :allow_nil_phase, :skip_billing_event

  after_create :setup_defaults
  after_update :update_linked_resources
  after_update :toggle_active_event, unless: Proc.new { |i| i.skip_billing_event }

  # Return the start of the current billing period.
  #
  def current_period

    previous_period = billing_usages.order(created_at: :desc).first

    # If we have no previous usage, and no billing events, we take the initial event creation timestamp
    if previous_period.nil? && billing_events.where(to_status: true).empty?
      # if no billing events, we take the created at timestamp for this object
      initial_subscription_creation = subscription.billing_events.where(to_status: true, subscription_product_id: nil).order(created_at: :desc).first
      return initial_subscription_creation.nil? ? created_at.utc : initial_subscription_creation.created_at.utc
    elsif previous_period.nil?
      return billing_events.where(to_status: true).order(created_at: :desc).first.created_at.utc
    end

    existing_status_event = billing_events.where(to_status: true).order(created_at: :desc).first

    return previous_period.period_end + 1.second if existing_status_event.nil?
    # If the previous period ended after the billing event, that is our timestamp
    return previous_period.period_end + 1.second if previous_period.period_end > existing_status_event.created_at.utc
    existing_status_event.created_at.utc
  end

  def linked_obj
    subscription.linked_obj
  end

  def pause!
    return true unless active
    update active: false
  end

  def unpause!
    return true if active
    update active: true
  end

  ##
  # Generate usage data for this subscription product
  #
  # Allow specifying end time for consistent data.
  #
  def generate_usage!(end_time = Time.now.utc)
    return false if product.nil?
    return false if current_price.nil?
    return false if linked_obj.nil?
    return false if billing_usages.where('period_start > ? and period_end <= ?', current_period, end_time).exists?
    raw_units = product.unit.nil? ? current_qty : ( current_qty / product.unit )
    if product.is_aggregated
      raw_units = raw_units - billing_usages.order(created_at: :desc).first.qty if billing_usages.exists?
      product_rate = if billing_usages.exists?
                       current_price raw_units + billing_usages.where("period_end >= ?", 30.days.ago).sum(:qty) # Intentionally not using `qty_total`.
                     else
                       current_price raw_units
                     end
      usage_total = product_rate.price * billable_qty(raw_units)
    else
      product_rate = current_price raw_units
      # Convert time difference into fractional hour.
      period_length = ((end_time - current_period).to_f / 1.hour).round(4)
      # Multiply price by fractional hour to get adjusted price, then multiply by quantity.
      usage_total = ((product_rate.price * period_length) * billable_qty(raw_units))
    end
    usage_total = usage_total.round 8
    usage_item = billing_usages.new(
      user: user,
      period_start: current_period,
      period_end: end_time,
      external_id: subscription.external_id,
      qty: billable_qty(raw_units),
      qty_total: raw_units,
      rate: product_rate.price,
      total: usage_total
    )
    if usage_total.zero?
      usage_item.processed = true
      usage_item.processed_on = Time.now
    end
    usage_item.save
  end

  def current_qty
    return 0 if linked_obj.nil?
    case product.resource_kind
    when 'cpu'
      linked_obj.cpu
    when 'memory'
      linked_obj.memory
    when 'backup'
      linked_obj.billing_backup_usage
    when 'bandwidth'
      linked_obj.billing_current_bandwidth
    when 'storage'
      linked_obj.billing_volume_usage
    when 'local_disk'
      linked_obj.billing_local_disk_usage
    else
      1
    end
  end

  # Qty, less qty included in their package
  def billable_qty(raw_units)
    return 1.0 if package
    included_units = case product.resource_kind
                     when 'backup'
                       subscription.package.backup
                     when 'storage'
                       subscription.package.storage
                     when 'local_disk'
                       subscription.package.local_disk
                     when 'bandwidth'
                       subscription.package.bandwidth
                     else
                       0.0
                     end
    return 0.0 if included_units.nil?
    raw_units > included_units ? (raw_units - included_units) : 0.0
  end

  ##
  # Determine current price. Returns it in hourly
  def run_rate
    return 0e0 if current_price.nil?
    case current_price&.term
    when 'month'
      current_price.price / 730.0
    when 'year'
      current_price.price / 8760.0
    else
      current_price.price
    end
  end

  def current_price(qty = nil)
    return nil if billing_resource.nil?
    # Subscription has no knowledge of QTY.
    if qty.nil?
      prices.where("billing_resource_prices.max_qty is null").first
    else
      prices.where("billing_resource_prices.max_qty is null OR billing_resource_prices.max_qty <= ?", qty).first
    end
  end

  def prices
    return BillingResourcePrice.where("2 = 3") if billing_resource.nil?
    return billing_resource.prices.where("2 = 3") if subscription.nil? || subscription.user.nil?
    currency = subscription.user.currency
    return billing_resource.prices.where("2 = 3") if currency.blank?
    billing_resource.prices.where("currency = '#{currency}' AND billing_phases.phase_type = ?", phase_type).joins(:billing_phase).order(Arel.sql("max_qty ASC NULLS LAST"))
  end

  ##
  # Auto-Advance phases
  #  - Runs hourly
  #  - Will skip if phase is already in 'final'.
  #  - Creates BillingChangeEvent on change
  #
  # Make sure we're in the correct phase, and if not, migrate.
  def validate_phase!
    return true if phase_type == 'final'
    billing_plan = user.billing_plan
    if billing_plan.nil? && phase_type.nil?
      update phase_type: 'final'
      return true
    end
    expected_phase = billing_resource.determine_phase(self)
    current_phase = phase_type
    return true if expected_phase == current_phase
    update phase_type: expected_phase
    billing_events.create!(
      subscription: self.subscription,
      from_phase: current_phase,
      to_phase: expected_phase
    )
  end

  private

  # - Set start_on, if nil. [default: subscription.created_at]
  # - set initial phase, if nil
  def setup_defaults
    update(start_on: subscription.created_at) if start_on.nil?
    if billing_plan.nil? && phase_type.nil?
      update phase_type: 'final'
    elsif phase_type.nil? && billing_resource
      update phase_type: billing_resource.determine_phase(self)
    end
  end

  # END setup_defaults

  # IF this is the package of a subscription, and we're linked
  # be sure to update the cpu/memory values of the linked obj.
  def update_linked_resources
    subscription.linked_obj&.update(
      cpu: package.cpu,
      memory: package.memory
    ) if package
  end

  def toggle_active_event
    if saved_change_to_attribute?("active")
      be = if active
             billing_events.new( from_status: false, to_status: true )
           else
             billing_events.new( from_status: true, to_status: false )
           end
      be.audit = current_audit if current_audit
      be.subscription = subscription
      be.save
      # Moving from Active to Inactive
      generate_usage! unless active
    end
  end

end
