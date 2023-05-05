##
# Subscription Product
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute active
#   @return [Boolean]
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

  scope :active, -> { where active: true }

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

  after_create_commit :init_usage!
  after_commit :purge_subscription_cache!

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

  # Is this a package/image, or a metered resource like storage?
  # Used to determine how we setup usage calculation.
  def product_is_resource?
    return true if product.nil?
    product.is_resource?
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
      # period_length = ((end_time - current_period).to_f / 1.hour).round(4)
      # Multiply price by fractional hour to get adjusted price, then multiply by quantity.
      # usage_total = ((product_rate.price_in_hourly * period_length) * billable_qty(raw_units))
      usage_total = product_rate.prorated_total current_period, end_time, billable_qty(raw_units)
    end

    # Monthly packages & images
    unless product_is_resource?
      unless product_rate.per_hour?
        unless billing_usages.where("period_end > ?", Time.now.utc).exists?
          # We don't have an active usage item
          increment_monthly_usage! product_rate
        end
        return
      end
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
      rate_period: product_rate.rate_term, # Only used to show what term the rate is in.
      total: usage_total
    )
    if usage_total.zero?
      usage_item.processed = true
      usage_item.processed_on = Time.now.utc
    end
    usage_item.save
  end

  def current_qty
    return 0 if linked_obj.nil?
    return 1 if product.is_image? || product.is_addon?
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
    return 1.0 if product.is_package?

    # images and addons are not included in packages, therefore we will not proceed.
    if product.is_image? || product.is_addon?
      # per_container == 1.0
      return 1.0 if billing_resource.bill_per_container?

      # sanity check
      return 1.0 if linked_obj.nil? || !linked_obj.is_a?(Deployment::Container)

      # If we only have 1 container
      return 1.0 if linked_obj.service.containers.count == 1

      # Provide a fraction for just this container.
      return (1.0 / linked_obj.service.containers.count.to_f).round(4)
    end

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
    expected_phase = billing_resource.determine_phase self
    current_phase = phase_type
    return true if expected_phase == current_phase
    update phase_type: expected_phase
    billing_events.create!(
      subscription: subscription,
      from_phase: current_phase,
      to_phase: expected_phase
    )
  end

  # For monthly billed resources, upon a change in product,
  # update active usage item's end date to today to avoid double billing.
  def prorate_usage!
    return if billing_resource.nil?
    return if product_is_resource? # only images/packages can get here.
    # Only if prorata is allowed.
    return unless billing_resource.prorate
    # Only if we have an active usage item.
    return unless billing_usages.where("period_end > ?", Time.now.utc).exists?
    existing_usage_items = billing_usages.where("period_end > ?", Time.now.utc)
    if existing_usage_items.count > 1
      ids = existing_usage_items.map {|i| i.id}
      SystemEvent.create!(
        message: "Fatal error adjusting usage item: #{id}",
        data: {
          subscription: subscription.id,
          product: product&.id,
          subscription_product: id,
          errors: "Multiple active usage items found, halting: #{ids.join(', ')}"
        },
        event_code: "287c90bc647e070b"
      )
      return
    end
    item = existing_usage_items.first
    hourly_rate = (item.rate / item.rate_period.to_f).round(4)
    Audit.create!(
      user: current_user,
      ip_addr: current_user.nil? ? '127.0.0.1' : current_user.last_request_ip,
      event: 'updated',
      rel_id: item.id,
      rel_model: item.class.to_s,
      raw_data: "Adjust usage due to SubscriptionProduct (#{id}) change."
    )
    updated_total = BillingResourcePrice.prorated_total(hourly_rate, 4, item.period_start, Time.now.utc, item.qty)
    if item.update(period_end: Time.now.utc, total: updated_total)
      purge_subscription_cache!
      true
    else
      SystemEvent.create!(
        message: "Fatal error adjusting usage item: #{id}",
        data: {
          subscription: subscription.id,
          product: product&.id,
          subscription_product: id,
          errors: "Error updating item: #{item.errors.full_messages.join(". ")}"
        },
        event_code: "33bf4620893b3193"
      )
      false
    end
  end

  # For monthly billed resources, initiate usage item upon creation.
  def init_usage!
    return if billing_resource.nil?
    return if product_is_resource? # only images/packages can get here.
    return if billing_resource.billed_hourly?
    # Only if we don't have an active usage item.
    return if billing_usages.where("period_end > ?", Time.now.utc).exists?
    r = current_price 1
    return if r.nil?
    period_start = Time.now.utc
    period_end = TimeHelpers.last_day_of_month
    total_usage = r.prorated_total(period_start, period_end, 1)
    new_usage_item = billing_usages.new(
      user: user,
      period_start: Time.now.utc,
      period_end: TimeHelpers.last_day_of_month,
      external_id: subscription.external_id,
      qty: 1,
      qty_total: 1,
      rate: r.price,
      rate_period: 730,
      total: total_usage
    )
    if total_usage.zero?
      new_usage_item.processed = true
      new_usage_item.processed_on = Time.now.utc
    end
    if new_usage_item.save
      purge_subscription_cache!
    else
      SystemEvent.create!(
        message: "Fatal error setting up monthly usage item: #{id}",
        data: {
          subscription: subscription.id,
          product: product&.id,
          subscription_product: id,
          errors: new_usage_item.errors.full_messages.join(". ")
        },
        event_code: "523b36509dc7e14a"
      )
    end
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

  # Any change to a product should immediately purge the run rate cache.
  def purge_subscription_cache!
    subscription.related.each do |i|
      next unless i.is_a?(Deployment::Container)
      next if i.deployment.nil?
      Rails.cache.delete("d_run_rate_#{i.deployment.id}")
      next if i.service.nil?
      Rails.cache.delete("s_run_rate_#{i.service.id}")
    end
  end

  # @param [BillingResourcePrice] product_rate
  # @return [Boolean]
  def increment_monthly_usage!(product_rate)
    return true if billing_usages.where("period_end > ?", Time.now.utc).exists?

    if Date.today.end_of_month == Date.today
      # We are on the last day, so create a new usage item beginning the 1st of next month
      period_start = TimeHelpers.next_month
      period_end = TimeHelpers.last_day_of_given_month period_end
    else
      # Otherwise, we use this month
      period_start = TimeHelpers.first_day_of_month
      period_end = TimeHelpers.last_day_of_month
    end

    new_usage_item = billing_usages.new(
      user: user,
      period_start: period_start,
      period_end: period_end,
      external_id: subscription.external_id,
      qty: 1, # Monthly, non-resource items, are always qty:1
      qty_total: 1,
      rate: product_rate.price,
      rate_period: 730,
      total: product_rate.price
    )
    if product_rate.price.zero?
      new_usage_item.processed = true
      new_usage_item.processed_on = Time.now.utc
    end
    if new_usage_item.save
      purge_subscription_cache!
      true
    else
      SystemEvent.create!(
        message: "Fatal error incrementing usage item: #{id}",
        data: {
          subscription: subscription.id,
          product: product&.id,
          subscription_product: id,
          errors: new_usage_item.errors.full_messages.join(". ")
        },
        event_code: "f511a3ca46c2f1a7"
      )
      false
    end
  end

end
