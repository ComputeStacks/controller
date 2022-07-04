##
# Container Image Volume Parameter
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute label
#   @return [String]
#
# @!attribute mount_path
#   @return [String] Where the volume is mounted inside the container.
#
# @!attribute enable_sftp
#   @return [Boolean]
#
# @!attribute borg_enabled
#   @return [Boolean]
#
# @!attribute borg_enabled
#   @return [Boolean] Backups
#
# @!attribute borg_freq
#   @return [String] A cron string
#
# @!attribute borg_strategy
#   @return [file,mysql]
#
# @!attribute borg_keep_hourly
#   @return [Integer] How many hourly backups to keep
#
# @!attribute borg_keep_daily
#   @return [Integer] How many daily backups to keep
#
# @!attribute borg_keep_weekly
#   @return [Integer] How many weekly backups to keep
#
# @!attribute borg_keep_monthly
#   @return [Integer] How many monthly backups to keep
#
# @!attribute borg_keep_annually
#   @return [Integer] How many annual backups to keep
#
# @!attribute borg_pre_backup
#   @return [Array<String>] a list of commands to run inside the container before a backup is taken.
#
# @!attribute borg_post_backup
#   @return [Array<String>] a list of commands to run inside the container after a backup is taken.
#
# @!attribute borg_pre_restore
#   @return [Array<String>] a list of commands to run inside the container before a restore takes place.
#
# @!attribute borg_post_restore
#   @return [Array<String>] a list of commands to run inside the container after a restore occurs.
#
# @!attribute borg_rollback
#   @return [Array<String>] a list of commands to run inside the container when a backup fails.
#
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
class ContainerImage::VolumeParam < ApplicationRecord

  include Auditable

  include Volumes::BorgPolicy
  include Volumes::VolumeMount

  belongs_to :container_image
  belongs_to :source_volume, class_name: 'ContainerImage::VolumeParam', optional: true

  has_many :volumes, class_name: "Volume", foreign_key: "template_id", dependent: :nullify
  has_many :dependent_volumes, class_name: 'ContainerImage::VolumeParam', foreign_key: 'source_volume_id', dependent: :restrict_with_error

  validates :borg_strategy, inclusion: { in: %w(file mysql postgres) }
  validates :label, presence: true
  validates :mount_path, presence: true
  validate :prevent_dependency_loop

  validate :valid_mount_point?

  before_validation :set_from_source

  # def local_csrn
  #   "csrn:caas:template:vol:#{resource_name}:#{id}"
  # end
  #
  # def local_resource_name
  #   return "null" if label.blank?
  #   label.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]
  # end

  # For ref volumes, we return the parent volume CSRN since this
  # record becomes simply a placeholder.
  def csrn
    return source_volume.csrn if source_volume
    "csrn:caas:template:vol:#{resource_name}:#{id}"
  end

  def resource_name
    return source_volume.resource_name if source_volume
    return "null" if label.blank?
    label.strip.downcase.gsub(/[^a-z0-9\s]/i,'').gsub(" ","_")[0..10]
  end

  # List volumes that are available to this user, which may be cloned
  def available_to_clone
    return [] unless current_user
    Volume.find_all_for(current_user).where("volumes.template_id = ?", id)
  end

  # List snapshots that are available to this user, which may be restored to this new volume
  def available_to_restore
    return [] unless current_user
    ar = []
    available_to_clone.each { |i| ar << i }
    ar.empty? ? [] : ar.flatten
  end

  private

  def set_from_source
    self.label = source_volume.label if source_volume
  end

  def valid_mount_point?
    if !id.nil? && container_image.volumes.where("id != ? and mount_path = ?", id, mount_path).exists?
      errors.add(:mount_path, 'already exists')
    elsif id.nil? && container_image.volumes.where(mount_path: mount_path).exists?
      errors.add(:mount_path, 'already exists')
    end
  end

  def prevent_dependency_loop
    # Ensure our source volume doesn't belong to an image that also requires a volume from us
  end

end
