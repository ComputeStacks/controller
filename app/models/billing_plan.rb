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

  after_save :update_default_plan
  after_save :clone_plan

  attr_accessor :clone

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

end
