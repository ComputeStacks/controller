##
# Billing Events
#
# This model is used to track changes to products. Upgrades and downgrades. We also generate webhooks from these events.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute from_status
#   @return [Boolean]
#
# @!attribute to_status
#   @return [Boolean]
#
# @!attribute from_phase
#   @return [trial,discount,final]
#
# @!attribute to_phase
#   @return [trial,discount,final]
#
# @!attribute resource_type
#   @return [String] cpu, memory, etc.
#
# @!attribute from_resource_qty
#   @return [Integer]
#
# @!attribute to_resource_qty
#   @return [Integer]
#
# @!attribute subscription
#   @return [Subscription]
#
# @!attribute source_product
#   @return [Product]
#
# @!attribute destination_product
#   @return [Product]
#
class BillingEvent < ApplicationRecord

  default_scope { order(created_at: :desc) }

  belongs_to :performed_by, class_name: 'User', foreign_key: 'user_id', optional: true
  belongs_to :subscription_product, optional: true
  belongs_to :subscription, optional: true # Used for tracking global subscription changes. i.e. cancellations.
  belongs_to :audit, optional: true

  belongs_to :source_product, class_name: 'Product', foreign_key: 'from_product_id', optional: true
  belongs_to :destination_product, class_name: 'Product', foreign_key: 'to_product_id', optional: true

  has_one :user, through: :subscription

  after_commit :init_webhook!, on: :create

  def linked_obj
    return nil if self.rel_model.nil?
    eval("#{self.rel_model}").find_by(id: self.rel_id)
  end

  def url(admin = true)
    return nil if self.linked_obj.nil?
    case self.rel_model
    when 'Deployment::Container'
      admin ? "/admin/deployments/#{self.linked_obj.deployment.token}/containers/#{self.rel_id}" : "/deployments/#{self.linked_obj.deployment.token}/containers/#{self.rel_id}"
    else
      nil
    end
  end

  private

  def init_webhook!
    WebHookJob.perform_later(self)
  end

end
