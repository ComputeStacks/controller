##
# Billing Resource Price
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute billing_phase
#   @return [BillingPhase]
#
# @!attribute billing_resource
#   @return [BillingResource]
#
# @!attribute currency
#   @return [String]
#
# @!attribute max_qty
#   @return [Decimal] Used to create tiered pricing by quantity. `max_qty` will be the maximum qty that this price will apply to.
#
# @!attribute price
#   @return [Decimal]
#
class BillingResourcePrice < ApplicationRecord

  include Auditable

  scope :sorted, -> { order(Arel.sql("max_qty asc nulls last")) }

  belongs_to :billing_phase
  belongs_to :billing_resource
  has_one :billing_plan, through: :billing_resource
  has_and_belongs_to_many :regions

  has_one :product, through: :billing_resource

  before_save :set_term!

  before_validation :ensure_unique_max_qty

  before_create :set_defaults

  def self.available_currencies
    c = BillingResourcePrice.select( Arel.sql( %Q( DISTINCT(currency) ) ) ).map { |i| i.currency }
    c.empty? ? %W( #{ENV['CURRENCY']} ) : c
  rescue
    %W( #{ENV['CURRENCY']} )
  end

  def bill_per_service?
    billing_resource.bill_per_service?
  end

  def bill_per_container?
    billing_resource.bill_per_container?
  end

  # @return [Float]
  def price_in_hourly
    price / rate_term.to_f
  end

  # @return [Integer]
  def rate_term
    case term
    when 'month'
      730
    when 'year'
      8760
    else
      1 # hourly
    end
  end

  # @return [Float]
  def prorated_total(period_start, period_end, qty = 1)
    p = price_in_hourly
    BillingResourcePrice.prorated_total p, price_precision, period_start, period_end, qty
  end

  # @return [Float]
  def self.prorated_total(p, price_precision, period_start, period_end, qty)
    return 0e0 if p.zero?
    # Convert time difference into fractional hour.
    l = TimeHelpers.fractional_compare period_start, period_end, price_precision
    # Multiply price by fractional hour to get adjusted price, then multiply by quantity.
    (p * l) * qty
  end

  def per_hour?
    term == 'hour'
  end

  def per_month?
    term == 'month'
  end

  def per_year?
    term == 'year'
  end

  def price_precision
    per_hour? ? 4 : 2
  end

  # Helper method to determine what our default term should be
  # Users can not set a term directly on a price.
  def default_term
    if product.nil?
      'hour'
    elsif product.is_aggregated
      'month'
    elsif product.kind == 'resource'
      'hour'
    else
      billing_plan.term
    end
  end

  private

  def set_defaults
    if self.billing_phase.nil?
      final_phase = self.billing_resource.billing_phases.find_by(phase_type: 'final')
      if final_phase.nil?
        final_phase = self.billing_resource.billing_phases.create!(phase_type: 'final')
      end
      self.billing_phase = final_phase
    end
  end

  def set_term!
    self.term = default_term
  end

  def ensure_unique_max_qty
    if regions.empty?
      errors.add(:regions, 'must have at least one selected')
      return
    end
    if max_qty.nil?
      rids = regions.map {|i| i.id}.join(', ')
      query = if id.blank?
                %Q( max_qty IS NULL AND regions.id IN (#{rids}) AND currency = '#{currency}' )
              else
                %Q( billing_resource_prices.id != #{id} AND (max_qty IS NULL AND regions.id IN (#{rids})) AND currency = '#{currency}' )
              end
      if billing_phase.prices.where( Arel.sql( query ) ).joins(:regions).exists?
        errors.add(:max_qty, 'value already exists')
      end
    elsif max_qty < 1
      errors.add(:max_qty, 'must be a positive value, or blank')
    else
      rids = regions.map {|i| i.id}.join(', ')
      query = if id.blank?
                %Q( max_qty = #{max_qty.to_f} AND regions.id IN (#{rids}) AND currency = '#{currency}' )
              else
                %Q( billing_resource_prices.id != #{id} AND (max_qty = #{max_qty.to_f} AND regions.id IN (#{rids})) AND currency = '#{currency}' )
              end
      if billing_phase.prices.where( Arel.sql( query ) ).joins(:regions).exists?
        errors.add(:max_qty, 'value already exists')
      end if billing_phase
    end

  end

end
