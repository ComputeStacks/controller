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
# @!attribute raw_text
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

  has_many :trashed_volumes, class_name: 'Volume', foreign_key: 'trashed_by_id', dependent: :nullify

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
    l = self.rel_model.blank? || self.rel_id.nil? ? nil : eval("#{self.rel_model}").find_by(id: self.rel_id)
    if l.nil? && !(self.rel_model.blank? && self.rel_uuid.blank?)
      l = eval("#{self.rel_model}").find_by(id: self.rel_uuid)
    end
    l = related_linked[0] if l.nil? && !raw_data.blank?
    l
  end

  def related_linked
    ar = []
    case rel_model
    when "Dns::ZoneCollaborator", "ContainerImageCollaborator", "ContainerRegistryCollaborator", "DeploymentCollaborator"
      ar << User.find_by(id: raw_data['user_id']) if raw_data['user_id']
      ar << Deployment.find_by(id: raw_data['deployment_id']) if raw_data['deployment_id']
      ar << Dns::Zone.find_by(id: raw_data['dns_zone_id']) if raw_data['dns_zone_id']
      ar << ContainerImage.find_by(id: raw_data['container_image_id']) if raw_data['container_image_id']
      ar << ContainerRegistry.find_by(id: raw_data['container_registry_id']) if raw_data['container_registry_id']
    when "Order"
      ar << linked.deployment unless linked.nil?
    end
    ar
  end

  def formatted_user
    self.user.nil? ? 'system' : self.user.email
  end

  def formatted_name
    r = []
    name = linked_name
    return raw_data unless raw_data.blank? || raw_data.is_a?(Hash)
    name = raw_data.dig(:name) if name.nil? && raw_data.is_a?(Hash)
    r << 'a' if name.blank?
    r << case rel_model
         when "Deployment::Container"
           'container'
         when 'Deployment::ContainerDomain'
           'domain'
         when "Deployment::ContainerService"
           'container service'
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
    when 'Deployment::ContainerDomain'
      linked.domain
    when "User"
      linked.full_name
    when "ContainerImage", "Deployment::ContainerService", "LoadBalancer", "Network", "Node", "Subscription"
      linked.label
    when 'Order'
      linked.id
    when "ContainerImageCollaborator", "ContainerRegistryCollaborator", "DeploymentCollaborator"
      linked.collaborator.full_name
    else
      nil
    end
  end

  def raw_formatter
    return "" if self.raw_data.blank?
    if self.raw_data.is_a?(Hash)
      d = self.raw_data.dup
      d.each do |k,v|
        if v.is_a?(ActiveSupport::TimeWithZone)
          d[k] = v.to_s
        end
      end
      d.to_yaml
    else
      self.raw_data
    end
  rescue
    self.raw_data
  end

end
