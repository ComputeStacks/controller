##
# Audit Trail
#
# @!attribute rel_model
#   @return [String] Name of the model. Used to dynamically find related.
#
# @!attribute rel_id
#   @return [Integer] ID of model
#
# @!attribute rel_uuid
#   @return [String] UUID of model (if applicable)
#
# @!attribute raw_data
#   @return [String] Raw details about this audit. Generally not used as we prefer to store data in Events.
#
# @!attribute ip_addr
#   @return [inet] IP of user who performed action. `127.0.0.1` is used with system events.
#
# @!attribute event
#   @return [String] 1-word to describe the event. Examples include: `created`, `updated`, `deleted`.
#
# EVENTS:
# created
# updated
# deleted
# exported
# imported
# restored
# rebuilt
# resized
#
class Audit < ApplicationRecord
  scope :sorted, -> { order(created_at: :desc) }

  belongs_to :user, optional: true
  has_many :system_events, dependent: :nullify
  has_many :event_logs, dependent: :nullify
  has_many :billing_events, dependent: :nullify

  has_many :trashed_volumes, class_name: "Volume", foreign_key: "trashed_by_id", dependent: :nullify

  serialize :raw_data

  def self.create_from_object!(obj, event, ip_addr, user = nil)
    Audit.create!(
      event: event,
      rel_id: obj.id,
      rel_model: obj.class,
      ip_addr: ip_addr,
      user: user
    )
  end

  def linked
    l = direct_linked
    l = related_linked[0] if l.nil? && !raw_data.blank?
    l
  end

  # Resolve the audited record itself, without the raw_data fallback.
  # `related_linked` must use this (not `linked`) to avoid infinite recursion
  # when the audited record no longer exists.
  def direct_linked
    l = (rel_model.blank? || rel_id.nil?) ? nil : eval("#{rel_model}").find_by(id: rel_id)
    if l.nil? && !(rel_model.blank? && rel_uuid.blank?)
      l = eval("#{rel_model}").find_by(id: rel_uuid)
    end
    l
  end

  def related_linked
    ar = []
    case rel_model
    when "Dns::ZoneCollaborator", "ContainerImageCollaborator", "ContainerRegistryCollaborator", "DeploymentCollaborator"
      ar << User.find_by(id: raw_data["user_id"]) if raw_data["user_id"]
      ar << Deployment.find_by(id: raw_data["deployment_id"]) if raw_data["deployment_id"]
      ar << Dns::Zone.find_by(id: raw_data["dns_zone_id"]) if raw_data["dns_zone_id"]
      ar << ContainerImage.find_by(id: raw_data["container_image_id"]) if raw_data["container_image_id"]
      ar << ContainerRegistry.find_by(id: raw_data["container_registry_id"]) if raw_data["container_registry_id"]
    when "Order"
      order = direct_linked
      ar << order.deployment unless order.nil?
    end
    ar
  end

  def formatted_user
    user.nil? ? "system" : user.email
  end

  def formatted_name
    r = []
    name = linked_name
    return raw_data unless raw_data.blank? || raw_data.is_a?(Hash)
    name = raw_data.dig(:name) if name.nil? && raw_data.is_a?(Hash)
    r << "a" if name.blank?
    r << case rel_model
    when "Deployment::Container"
      "container"
    when "Deployment::ContainerDomain"
      "domain"
    when "Deployment::ContainerService"
      "container service"
    else
      rel_model&.downcase
    end
    r << name unless name.blank?
    r
  end

  def linked_name
    return nil if linked.nil?
    case linked.class.name
    when "Deployment", "Deployment::Container", "Deployment::Sftp", "Location", "Region", "Volume"
      linked.name
    when "Deployment::ContainerDomain"
      linked.domain
    when "User"
      linked.full_name
    when "ContainerImage", "Deployment::ContainerService", "LoadBalancer", "Network", "Node", "Subscription"
      linked.label
    when "Order"
      linked.id
    when "ContainerImageCollaborator", "ContainerRegistryCollaborator", "DeploymentCollaborator"
      linked.collaborator.full_name
    end
  end

  def raw_formatter
    return "" if raw_data.blank?
    if raw_data.is_a?(Hash)
      d = raw_data.dup
      d.each do |k, v|
        if v.is_a?(ActiveSupport::TimeWithZone)
          d[k] = v.to_s
        end
      end
      d.to_yaml
    else
      raw_data
    end
  rescue
    raw_data
  end
end
