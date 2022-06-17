##
# Volume Map
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute volume
#   @return [Volume]
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute mount_path
#   @return [String] Where the volume is mounted inside of the container.
#
# @!attribute mount_ro
#   @return [Boolean] Defaults to false
#
# @!attribute is_owner
#   @return [Boolean] Owner map is the primary mount, where backup rules etc are referenced from.
#
class VolumeMap < ApplicationRecord

  include Auditable
  include Volumes::VolumeMount

  scope :primary, -> { where is_owner: true }

  belongs_to :volume
  belongs_to :container_service, class_name: 'Deployment::ContainerService'
  has_one :deployment, through: :container_service
  has_many :containers, through: :container_service

  validates :mount_path, format: {with: /[\x00-\x1F\/\\:\*\?\"<>\|]/u}
  validates :mount_path, presence: true, uniqueness: { scope: :container_service }
  validate :no_nested_volumes

  before_destroy :ensure_not_primary

  private

  def ensure_not_primary
    return true unless is_owner
    errors.add(:base, "unable to delete primary mount")
    false
  end

  # A volume may not be above another volume in the path.
  def no_nested_volumes
    return nil if container_service.nil?
    is_parent = false
    container_service.volume_maps.where.not(id: id).pluck(:mount_path).each do |i|
      is_parent = true if i.start_with?(mount_path) # Is our new path is above an existing path?
      is_parent = true if mount_path.start_with?(i) # Is our new path below an existing path?
      break if is_parent # no need to keep checking
    end
    errors.add(:mount_path, "is already in use.") if is_parent
  end

end
