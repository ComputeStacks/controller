##
# Container Image Provider
#
# Each container image is associated with a _provider_ object, which holds any authentication details and URL.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute is_default
#   @return [Boolean]
#
# @!attribute hostname
#   @return [String]
#
# @!attribute container_registry
#   @return [ContainerRegistry] Each registry will have it's own provider
#
# @!attribute active
#   @return [Boolean]
#
class ContainerImageProvider < ApplicationRecord

  include Auditable

  scope :find_default, -> {where is_default: true}
  scope :active, -> { where active: true }
  scope :sorted, -> { order( Arel.sql("lower(name)") )}

  has_many :container_images, dependent: :restrict_with_error
  has_many :image_variants, through: :container_images
  belongs_to :container_registry, optional: true
  has_one :user, through: :container_registry

  validate :check_hostname
  validate :enforce_dockerhub
  validate :check_default
  validates :name, presence: true
  validates :name, uniqueness: true

  before_destroy :can_destroy?

  after_save :toggle_default

  def is_dockerhub?
    return false if name.nil?
    name.strip.downcase == 'dockerhub' && hostname.strip.blank?
  end


  def name_with_url
    return self.name if self.hostname.blank?
    "#{self.name} (#{self.hostname})"
  end

  def name_with_user
    return name_with_url if self.user.nil?
    "#{self.name} (#{self.user.id}-#{self.user.full_name})"
  end

  private

  def check_hostname
    if is_dockerhub?
      unless hostname.blank?
        errors.add(:hostname, "DockerHub must have an empty hostname")
      end
    else
      if hostname.strip.blank? && container_registry.nil?
        errors.add(:hostname, "must be set if you haven't selected a registry.")
      end
    end
  end

  def enforce_dockerhub
    return true if name_in_database.nil?
    if name_changed? && name_in_database.downcase == 'dockerhub'
      errors.add(:name, "can't change the name of DockerHub.")
    end
  end

  def check_default
    return true if is_default_in_database.nil?
    if is_default_changed? && is_default_in_database
      errors.add(:is_default, "can't be unselected here.")
    end
  end

  def toggle_default
    if saved_change_to_is_default? && !is_default_before_last_save
      ContainerImageProvider.where("id != ? and is_default = true", id).update_all is_default: false
    end
  end

  def can_destroy?
    if is_default
      errors.add(:base, 'Unable to delete the default provider.')
      Audit.where(rel_model: self.class.name, rel_id: id, event: 'deleted').delete_all
      throw :abort
    elsif is_dockerhub?
      errors.add(:base, 'DockerHub is a required provider.')
      Audit.where(rel_model: self.class.name, rel_id: id, event: 'deleted').delete_all
      throw :abort
    elsif container_registry
      errors.add(:base, "Linked to registry, unable to delete.")
      throw :abort
    end
  end

end
