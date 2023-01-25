##
# Service Plugins
#
# @!attribute active
#   @return [Boolean]
# @!attribute is_optional
#   @return [Boolean]
#
class Deployment::ContainerService::ServicePlugin < ApplicationRecord

  include Auditable
  include ContainerServices::ServicePlugins::DemoServicePlugin
  include ContainerServices::ServicePlugins::MonarxServicePlugin

  scope :active, -> { where active: true }
  scope :optional, -> { where is_optional: true }

  belongs_to :container_service, class_name: "Deployment::ContainerService", foreign_key: 'deployment_container_service_id'
  belongs_to :container_image_plugin
  has_one :product, through: :container_image_plugin

  after_update :update_subscription

  def label
    container_image_plugin.label
  end

  # Given the plugin, apply parameters
  # @return [Hash] container runtime config
  def apply_plugin_config!(c = {})
    return c if c.empty?
    return c unless active
    return c unless container_image_plugin.available?
    case container_image_plugin.name
    when "monarx"
      monarx_config c
    else
      c
    end
  end

  # Can a user selectively enable or disable this plugin?
  # @return [Boolean]
  def user_selectable?
    return false unless is_optional
    case container_image_plugin.name
    when "monarx"
      container_image_plugin.monarx_available?
    else
      true
    end
  end

  private

  def update_subscription
    return if product.nil?
    return unless active_previously_changed?
    container_service.containers.each do |container|
      sp = container.subscription.subscription_products.find_by(product: product)
      if sp
        sp.current_audit = current_audit if current_audit
        sp.current_user = current_user if current_user
        active ? sp.unpause! : sp.pause!
      else
        sp = container.subscription.subscription_products.new(
          product: product,
          allow_nil_phase: true,
          active: active
        )
        sp.current_audit = current_audit if current_audit
        sp.current_user = current_user if current_user
        unless sp.save
          SystemEvent.create!(
            message: "fatal error creating service plugin subscription",
            data: {
              service: container_service.id,
              plugin: container_image_plugin.id,
              service_plugin: id,
              errors: sp.errors.full_messages
            },
            event_code: "24c37f1e950118c4"
          )
        end
      end
    end
  end

end
