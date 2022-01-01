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

  before_save :set_term

  before_validation :ensure_unique_max_qty

  before_create :set_defaults

  def self.available_currencies
    c = BillingResourcePrice.select( Arel.sql( %Q( DISTINCT(currency) ) ) ).map { |i| i.currency }
    c.empty? ? %W( #{ENV['CURRENCY']} ) : c
  rescue
    %W( #{ENV['CURRENCY']} )
  end

  def post_paid?
    per_hour? || product.is_aggregated
  end

  def pre_paid?
    !post_paid?
  end

  def per_hour?
    self.term == 'hour'
  end

  def per_month?
    self.term == 'month'
  end

  def per_year?
    self.term == 'year'
  end

  def price_precision
    4
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

  def set_term
    self.term = product&.is_aggregated ? 'month' : 'hour'
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
      end
    end

  end

end
