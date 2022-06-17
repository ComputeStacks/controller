##
# Subscription
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute label
#   @return [String]
#
# @!attribute active
#   Simple boolean indicator to note if this is an active subscription or not.
#   @return [Boolean]
#
# @!attribute user
#   @return [User]
#
# @!attribute subscription_products
#   @return [Array<SubscriptionProduct>]
#
# @!attribute products
#   @return [Array<Product>]
#
# @!attribute billing_usages
#   @return [Array<BillingUsage>]
#
# @!attribute billing_events
#   @return [Array<BillingEvent>]
#
# @!attribute container
#   @return [Deployment::Container]
#
# @!attribute volume
#   @return [Volume]
#
class Subscription < ApplicationRecord

  # user_id:integer
  # label:string
  # external_id:string # For tracking in external billing systems.
  # active:boolean
  # details:text # JSON store additional details when product is deleted.
  # service_key:string Helper method to find subscriptions automatically created by ComputeStacks.
  #
  # NOTES:
  #   - For Packages: Don't add subscription items for 'storage' and 'bandwidth.'
  #     - If they exist in the billing plan, we will automatically use that for overage billing.
  #   - multiple subscriptions can have the same external_id -- external_id's = qty reference
  #
  include Auditable

  scope :all_active, -> { where(active: true) }
  scope :sorted, -> { order(created_at: :desc) }

  belongs_to :user, optional: true
  has_many :subscription_products, dependent: :destroy
  has_many :products, through: :subscription_products
  has_many :billing_usages, through: :subscription_products

  has_many :billing_events

  has_one :container, class_name: 'Deployment::Container', dependent: :nullify

  has_one :volume, dependent: :nullify

  accepts_nested_attributes_for :container

  serialize :details, JSON

  after_update :toggle_active_event
  after_create_commit :trigger_create_event

  attr_accessor :current_audit

  def csrn
    "csrn:billing:subscription:root:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if label.blank?
    label.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]
  end

  # Public run rate, returns it in monthly!
  def run_rate
    total = 0e0
    self.subscription_products.each do |i|
      next if i.product.nil?
      case i.product.kind
      when 'resource'
        bu = i.billing_usages.first
        next if bu.nil?
        total += bu.hourly_run_rate
      when 'package'
        total += i.run_rate
      end
    end
    (total * 730.0).round(4)
  end

  # Returns all subscriptions in the same service
  def related
    return [] if linked_obj.nil? || linked_obj.service.nil?
    linked_obj.service.subscriptions.where.not(id: id) if linked_obj.is_a? Deployment::Container
  end

  def post_paid?
    return true if package.nil?
    sb = subscription_products.where("products.kind = 'package'").joins(:product).first
    return true if sb.nil? # shouldn't happen
    sb.current_price.post_paid?
  end

  def linked_obj
    return nil if container.nil?
    container
  end

  def package
    products.find_by(kind: 'package')&.package
  end

  def package_subscription
    subscription_products.where(products: { kind: 'package' }).joins(:product).first
  end

  # stops billing
  def pause!
    subscription_products.each do |i|
      i.pause!
    end
    update active: false
  end
  def unpause!
    subscription_products.each do |i|
      i.unpause!
    end
    update active: true
  end

  def cancel!
    update active: false
  end

  ##
  # Migrate to new package.
  #  - Create BillingEvent
  #
  def new_package!(new_package)
    current_package = package
    return false if current_package.nil? # package-to-package only.
    current_product = current_package.product
    return false if new_package.product.nil?
    return false if new_package.nil?
    sub_product = self.subscription_products.find_by(product: current_product)
    return false if sub_product.nil? # Error! Shouldn't be here.
    # Migrate the subscription.
    sub_product.update_attribute :product, new_package.product
    event = sub_product.billing_events.create!(
      source_product: current_product,
      destination_product: new_package.product,
      subscription: self
    )
    unless linked_obj.nil?
      event.update(
        rel_id: linked_obj.id,
        rel_model: linked_obj.class.to_s
      )
    end
    true
  end

  ##
  # Track change in resources
  # resources = {
  #   cpu => {'from' => qty, 'to' => qty},
  #   memory => {'from' => qty, 'to' => qty}
  # }
  def new_resource_qty!(resources)
    return false if package # Not allowed for packages.
    cpu_product = Product.lookup(user.billing_plan, 'cpu')
    cpu = subscription_products.find_by(product: cpu_product)
    mem_product = Product.lookup(user.billing_plan, 'memory')
    mem = subscription_products.find_by(product: mem_product)
    events = []
    if cpu.nil?
      cpu = subscription_products.create!(product: cpu_product, phase_type: 'final')
      cpu.reload
    end
    if mem.nil?
      mem = subscription_products.create!(product: mem_product, phase_type: 'final')
      mem.reload
    end
    events << cpu.billing_events.create!(
      from_resource_qty: resources['cpu']['from'],
      to_resource_qty: resources['cpu']['to']
    )
    events << mem.billing_events.create!(
      from_resource_qty: resources['memory']['from'],
      to_resource_qty: resources['memory']['to']
    )
    unless linked_obj.nil?
      events.each do |e|
        e.update(
          rel_id: linked_obj.id,
          rel_model: linked_obj.class.to_s
        )
      end
    end # END unless linked_obj
    true
  end # END new_resource_qty!()

  private

  # For new subscriptions, trigger event.
  def trigger_create_event
    return unless active # Only if we're active now.
    be = billing_events.new( from_status: false, to_status: true )
    be.audit = current_audit if current_audit
    be.save
  end

  # Capture updates to the active flag.
  def toggle_active_event
    if saved_change_to_attribute?("active")
      if active # Means we came from inactive, so now we're active.
        be = billing_events.new( from_status: false, to_status: true )
        # Ensure user's `phase_started` is set.
        user.update(phase_started: Time.now) if user && user.phase_started.nil?
      else
        be = billing_events.new( from_status: true, to_status: false )
      end
      be.audit = current_audit if current_audit
      be.save
    end
  end

end
