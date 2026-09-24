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
  validates :term, inclusion: {in: %w[hour month], message: "Must be one of: hour or month."}

  after_save :update_default_plan
  after_save :clone_plan

  after_update_commit :cascade_price_changes

  attr_accessor :clone

  # A plan is usable only once a product exists for each of these resource_kinds.
  # Compared downcased, matching Product.lookup's `lower(resource_kind)`.
  REQUIRED_RESOURCE_KINDS = %w[bandwidth storage local_disk].freeze

  ##
  # Plans that have at least one user but are missing a required product.
  #
  # Deliberately set-based. The previous version joined :users WITHOUT distinct,
  # so it instantiated one BillingPlan per USER and ran three Product.lookup
  # calls on each -- each of those a seq scan plus an association load per
  # matching product. Measured on production: 13,327 queries / 114s, which
  # gateway-timed-out the admin dashboard (the only caller). Now two queries.
  #
  # @return [Array<BillingPlan>]
  def self.invalid_plans
    in_use = BillingPlan.joins(:users).distinct
    present = resource_kinds_by_plan(in_use.select(:id))
    in_use.reject { |plan| (REQUIRED_RESOURCE_KINDS - present.fetch(plan.id, [])).empty? }
  end

  ##
  # Downcased resource_kind list for each of the given plan ids, in one query.
  # Inner join on :product is intentional: billing_resources.product_id is
  # nullable, and a resource with no product contributes no resource_kind.
  #
  # @param plan_ids [ActiveRecord::Relation, Array<Integer>]
  # @return [Hash{Integer => Array<String>}]
  def self.resource_kinds_by_plan(plan_ids)
    BillingResource.joins(:product)
      .where(billing_plan_id: plan_ids)
      .pluck(:billing_plan_id, Arel.sql("lower(products.resource_kind)"))
      .each_with_object({}) { |(plan_id, kind), acc| (acc[plan_id] ||= []) << kind }
  end
  private_class_method :resource_kinds_by_plan

  # Determine if all required products are added and it's ready to use.
  # @return [Boolean]
  def available?
    missing_required_products.empty?
  end

  ##
  # Required resource_kinds this plan has no product for, in REQUIRED_RESOURCE_KINDS
  # order. One query instead of three Product.lookup round trips -- this runs per row
  # on admin/billing_plans#index via #available?.
  #
  # @return [Array<String>]
  def missing_required_products
    REQUIRED_RESOURCE_KINDS - products.pluck(Arel.sql("lower(products.resource_kind)"))
  end

  # @return [Boolean]
  def billed_hourly?
    term == "hour"
  end

  # @return [Boolean]
  def billed_monthly?
    term == "month"
  end

  ##
  # Determine if the Product is available in this billing plan.
  # Used for API's.
  def product_available?(product)
    products.include?(product)
  end

  def available_currencies
    cur = prices.select(Arel.sql(%( DISTINCT(currency) )))
    (cur.nil? || cur.empty?) ? [] : cur.map { |i| i.currency }
  end

  # @param cpu [Float]
  # @param memory [Integer]
  def packages_by_resource(cpu, memory)
    BillingPackage.find_by_plan self, {cpu: cpu, memory: memory}
  end

  private

  def update_default_plan
    self.class.where("id != ? and is_default", id).update_all(is_default: false) if is_default
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
