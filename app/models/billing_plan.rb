##
# BillingPlan
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute is_default
#   @return [Boolean] deprecated
#
# @!attribute term
#   Sets price term for all items in this billing plan.
#   @return [String] hour,month
#
class BillingPlan < ApplicationRecord

  include Auditable

  scope :default, -> { find_by(is_default: true) }

  has_many :user_groups
  has_many :users, through: :user_groups, dependent: :restrict_with_error

  has_many :billing_resources, dependent: :destroy
  has_many :prices, through: :billing_resources
  has_many :products, through: :billing_resources
  has_many :billing_phases, through: :billing_resources

  validates :name, presence: true
  validates :term, inclusion: { in: %w(hour month), message: 'Must be one of: hour or month.' }

  after_save :update_default_plan
  after_save :clone_plan

  after_update_commit :cascade_price_changes

  attr_accessor :clone

  def self.invalid_plans
    result = []
    BillingPlan.joins(:users).each do |i|
      result << i unless i.available?
    end
    result
  end

  # Determine if all required products are added and it's ready to use.
  # @return [Boolean]
  def available?
    if Product.lookup(self, 'bandwidth').nil?
      return false
    end
    if Product.lookup(self, 'storage').nil?
      return false
    end
    if Product.lookup(self, 'local_disk').nil?
      return false
    end
    true
  end

  # @return [Array]
  def missing_required_products
    p = []
    p << 'bandwidth' if Product.lookup(self, 'bandwidth').nil?
    p << 'storage' if Product.lookup(self, 'storage').nil?
    p << 'local_disk' if Product.lookup(self, 'local_disk').nil?
    p
  end

  # @return [Boolean]
  def billed_hourly?
    term == 'hour'
  end

  # @return [Boolean]
  def billed_monthly?
    term == 'month'
  end

  ##
  # Determine if the Product is available in this billing plan.
  # Used for API's.
  def product_available?(product)
    self.products.include?(product)
  end

  def available_currencies
    cur = prices.select( Arel.sql( %Q( DISTINCT(currency) ) ) )
    cur.nil? || cur.empty? ? [] : cur.map { |i| i.currency }
  end

  # @param cpu [Float]
  # @param memory [Integer]
  def packages_by_resource(cpu, memory)
    BillingPackage.find_by_plan self, { cpu: cpu, memory: memory }
  end

  private

  def update_default_plan
    self.class.where('id != ? and is_default', self.id).update_all(is_default: false) if self.is_default
  end

  def clone_plan
    return if clone.nil?
    clone.billing_resources.each do |i|
      nr = i.dup
      nr.billing_plan_id = id
      nr.skip_default_phase = true
      nr.save

      i.prices.each do |ii|
        nph = ii.billing_phase.dup
        nph.billing_resource = nr
        nph.save

        npr = ii.dup
        npr.billing_resource = nr
        npr.billing_phase = nph
        npr.regions = ii.regions
        npr.save
      end
    end
  end

  # When changing a billing plan term, we also
  # need to cascade the update to all subordinate prices.
  def cascade_price_changes
    if term_previously_changed?
      billing_resources.each do |br|
        br.prices.each do |p|
          next if p.product.is_aggregated
          p.update term: term
        end
      end
    end
  end

end
