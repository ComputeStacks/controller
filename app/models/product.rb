##
# Product
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute label
#   @return [String]
#
# @!attribute kind
#   Must be one of:
#     * package
#     * image
#     * addon
#     * resource
#   @return [String]
#
# @!attribute resource_kind
#   Must be one of:
#     * backup
#     * bandwidth
#     * cpu
#     * ipaddr
#     * memory
#     * storage
#     * local_disk
#   @return [String]
#
# @!attribute unit
#   For memory, we recommend units of 256. All else should be 1.
#   @return [Integer]
#
# @!attribute unit_type
#   Can be GB, MB, Container License, or whatever else you're selling.
#   @return [String]
#
# @!attribute group
#   Used to group products on order page.
#   @return [String]
#
# @!attribute package
#   @return [BillingPackage]
#
# @!attribute billing_resources
#   @return [Array<BillingResource>]
#
# @!attribute prices
#   @return [Array<BillingResourcePrice>]
#
# @!attribute subscriptions
#   @return [Array<Subscription>]
#
# @!attribute subscription_products
#   @return [Array<SubscriptionProduct>]
#
# @!attribute containers
#   @return [Array<Deployment::Container>]
#
class Product < ApplicationRecord

  include Auditable

  scope :sorted, -> { order "lower(label)" }
  scope :packages, -> { where(kind: 'package' ) }
  scope :addons, -> { where(kind: 'addon' ) }
  scope :images, -> { where(kind: 'image' ) }
  scope :resources, -> { where(kind: 'resource' ) }

  has_many :billing_resources, dependent: :destroy
  has_many :prices, through: :billing_resources
  has_many :billing_plans, through: :billing_resources

  has_many :container_images, dependent: :nullify

  has_many :subscription_products, dependent: :restrict_with_error
  has_many :subscriptions, through: :subscription_products

  has_many :containers, class_name: 'Deployment::Container', through: :subscriptions
  has_one :package, class_name: 'BillingPackage', dependent: :destroy

  has_many :image_plugins, class_name: "ContainerImagePlugin", dependent: :nullify

  before_validation :set_defaults

  before_save :update_product_name
  before_save :set_aggregation

  validates :label, presence: true
  validates :kind, inclusion: { in: %w(resource package image addon), message: 'Must be one of: resource, package, image, addon' }
  validates :unit, numericality: { greater_than: 0 }, if: Proc.new { |product| product.kind == 'resource' }
  validates :unit_type, presence: true, if: Proc.new { |product| product.kind == 'resource' }

  accepts_nested_attributes_for :package

  def label_with_kind
    "#{label} (#{kind.titleize})"
  end

  def is_package?
    kind == 'package'
  end

  def is_image?
    kind == 'image'
  end

  def is_addon?
    kind == 'addon'
  end

  def is_resource?
    kind == 'resource'
  end

  # Find a particular price for a given user & region
  # Used by: Order Form
  # returns BillingResourcePrice
  def price_lookup(user, region, qty = 0)
    prices = price_phases(user, region)
    price = nil
    prices[:final].reverse.each do |i|
      price = i if i.max_qty.nil? || i.max_qty >= qty
    end
    prices[:discount].reverse.each do |i|
      price = i if i.max_qty.nil? || i.max_qty >= qty
    end
    prices[:trial].reverse.each do |i|
      price = i if i.max_qty.nil? || i.max_qty >= qty
    end
    price
  end

  def price_phases(user, region)
    result = {trial: [], discount: [], final: []}
    return result if region.nil?
    billing_plan = user.billing_plan
    return result if billing_plan.nil?
    resource = billing_resources.find_by(billing_plan: billing_plan)
    return result if resource.nil?
    available_prices = self.prices.where('billing_resource_id = ? AND regions.id = ?', resource.id, region).joins(:regions).order( Arel.sql("max_qty NULLS LAST") )
    available_prices.each do |i|
      case i.billing_phase.phase_type
      when 'trial'
        result[:trial] << i if i.billing_phase.in_phase?(user)
      when 'discount'
        result[:discount] << i if i.billing_phase.in_phase?(user)
      when 'final'
        result[:final] << i
      end
    end
    result
  end

  ##
  # User allowed to use this product?
  #
  # Simply checks that this product exists in their billing plan.
  #
  # NOTE: For packages, a false will prevent the user from ordering.
  #       For images, they can still order, but will not be charged for it!
  #
  # @return [Boolean]
  #
  def allow_user?(user)
    return false if user&.billing_plan.nil?
    billing_resources.where("billing_plans.id = ?", user.billing_plan.id).joins(:billing_plan).exists?
  end

  class << self

    # Temporary. Move labels to i18n.
    def resource_kinds
      [
        ['Disk', 'storage'],
        ['Local Disk', 'local_disk'],
        ['Bandwidth', 'bandwidth'],
        ['Backup & Image Storage', 'backup']
      ]
    end

    ##
    # Find product by billing plan, name
    #
    def lookup(billing_plan, name)
      product = nil
      Product.where("lower(resource_kind) = ?", name.downcase).each do |i|
        product = i if i.billing_plans.include?(billing_plan)
      end
      product
    end

  end

  private

  def set_defaults
    if kind.blank?
      self.kind = package ? "package" : "resource"
    end
    if unit.to_i.zero? && package
      self.unit = 1
    end

  end

  def set_aggregation
    self.is_aggregated = resource_kind == 'bandwidth'
  end

  def update_product_name
    self.name = label.parameterize
  end

end
