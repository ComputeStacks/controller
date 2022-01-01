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

  belongs_to :container_image

  validates :borg_strategy, inclusion: { in: %w(file mysql postgres) }
  validates :label, presence: true
  validates :mount_path, presence: true

  validate :valid_mount_point?

  private

  def valid_mount_point?
    if !id.nil? && container_image.volumes.where("id != ? and mount_path = ?", id, mount_path).exists?
      errors.add(:mount_path, 'already exists')
    elsif id.nil? && container_image.volumes.where(mount_path: mount_path).exists?
      errors.add(:mount_path, 'already exists')
    end
  end

end
