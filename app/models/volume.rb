##
# Volume
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] name
#   @return [String] UUID
#
# @!attribute label
#   @return [String]
#
# @!attribute container_path
#   @return [String] The path inside the container where the volume is mounted.
#
# @!attribute user
#   @return [User]
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute region
#   @return [Region]
#
# @!attribute to_trash
#   @return [Boolean] This is set when a user specifically deletes the associated service, or the volume.
#
# @!attribute trash_after
#   @return [DateTime] When `to_trash` is set, this date is set.
#
# @!attribute trashed_by
#   @return [User] the user who performed the trash operations
#
# @!attribute usage
#   @return [Integer] Current usage in GB.
#
# @!attribute usage_checked
#   @return [DateTime] When usage was last checked
#
# @!attribute detached_at
#   @return [DateTime] When the volume lost it's associate with it's service.
#
# @!attribute subscription
#   @return [Subscription] Only exists if it's detached.
#
# @!attribute enable_sftp
#   @return [Boolean] Whether or not the volume should be mounted inside the SFTP container.
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
# @!attribute volume_backend
#   @return [local,nfs] local is default.
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute containers
#   @return [Array<Deployment::Container>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
# @!attribute region
#   @return [Region]
#
# @!attribute location
#   @return [Location]
#
# @!attribute user
#   @return [User]
#
# @!attribute nodes
#   @return [Array<Node>]
#
# @!attribute event_logs
#   @return [Array<EventLog>]
#
class Volume < ApplicationRecord

  include Auditable
  include Authorization::Volume
  include UrlPathFinder
  include Volumes::BackupVolume
  include Volumes::BorgPolicy
  include Volumes::ConsulVolume
  include Volumes::VolumeDriver
  include Volumes::VolumeLookup

  scope :trashable, -> { where("to_trash = true and trash_after <= ?", Time.now) }
  scope :active, -> { where(to_trash: false) }
  scope :sorted, -> { order(created_at: :desc) }
  scope :sftp_enabled, -> { where(enable_sftp: true) }
  scope :all_local, -> { where(volume_backend: 'local') }

  belongs_to :container_service, class_name: 'Deployment::ContainerService', optional: true
  has_one :deployment, through: :container_service
  has_many :containers, through: :container_service

  has_many :collaborators, through: :deployment

  belongs_to :region, optional: true # optional is temporary while we transition.
  has_one :location, through: :region
  belongs_to :user, optional: true
  has_one :user_group, through: :user
  has_and_belongs_to_many :nodes

  # has_many :logs, class_name: 'Deployment::EventLog', dependent: :nullify
  has_and_belongs_to_many :event_logs
  has_many :audits, -> { where(rel_model: 'Volume') }, foreign_key: :rel_id, class_name: 'Audit', dependent: :nullify

  belongs_to :subscription, optional: true

  validates :label, presence: true
  validates :container_path, presence: true

  before_validation :set_name, on: :create

  before_save :set_trash_after #, if: :persisted?
  before_save :update_user, unless: :skip_user_update
  after_save :rebuild_services, if: :force_rebuild

  after_save :update_subscription

  after_commit :set_detached
  after_commit :update_consul!

  validates :name, presence: true, uniqueness: true
  validates :container_path, format: {with: /[\x00-\x1F\/\\:\*\?\"<>\|]/u}
  validate :ensure_single_path

  belongs_to :trashed_by, class_name: 'Audit', optional: true

  before_destroy :ensure_can_trash!

  # CurrentAudit: Audit in use for this job.
  # ProvisionVolume: Build the volume on the node
  # ForceRebuild: Useful after changes are made to the container service.
  attr_accessor :force_rebuild, :skip_user_update

  def can_trash?
    to_trash && trash_after <= Time.now
  end

  def operation_in_progress?
    event_logs.running.exists?
  end

  # Which container services can this volume be migrated to.
  def available_services
    d = []
    nodes.each do |node|
      node.container_services.each do |s|
        d << s unless d.include?(s)
      end
    end
    d
  end

  # Find all services attached to this volume.
  def attached_services
    result = {
      known: [],
      unknown: []
    }
    if region.nil? && !nodes.empty?
      self.update_column :region_id, nodes.first.region&.id
    end
    nodes.available.each do |i|
      i.list_all_containers.each do |c|
        c.info['Mounts'].each do |m|
          if m['Name'] == self.name
            cname = c.info['Names'].first.split('/').last
            cl = Deployment::Container.find_by(name: cname)
            cl = Deployment::Sftp.find_by(name: cname) if cl.nil?
            if cl.nil?
              result[:unknown] << {
                node: i,
                container: cname
              }
            else
              result[:known] << cl
            end
          end
        end
      end
    end
    result
  rescue => e
    ExceptionAlertService.new(e, 'cf7db317de13af0c').perform
    SystemEvent.create!(
      message: "Error loading volume services #{self.id}.",
      log_level: "warn",
      data: {
        volume: {
          id: self.id,
          name: self.name,
          user: self.user&.id
        },
        errors: e.message
      },
      event_code: 'cf7db317de13af0c'
    )
    nil
  end

  def find_node
    if !nodes.empty?
      nodes.first
    elsif container_service
      container_service.nodes.first
    elsif region
      region.nodes.available.first
    end
  end

  class << self

    # Exclude this volume from SFTP containers for specific roles.
    def excluded_roles
      db_roles + %w(pma)
    end

    # This is considered a database volumes for the following roles
    def db_roles
      %w(mysql postgres mariadb postgresql percona pg)
    end

  end

  private

  def set_trash_after
    if !trash_after && to_trash
      self.trash_after = Rails.env.production? ? 2.hours.from_now : Time.now
    elsif trash_after && !to_trash
      self.trash_after = nil
    end
  end

  def set_name
    self.name = SecureRandom.uuid.strip if self.name.blank?
  end

  # A volume may not be above another volume in the path.
  def ensure_single_path
    is_parent = false
    return nil if container_service.nil?
    container_service.volumes.where.not(id: self.id).pluck(:container_path).each do |i|
      is_parent = true if i.start_with?(container_path) # Is our new path is above an existing path?
      is_parent = true if container_path.start_with?(i) # Is our new path below an existing path?
    end
    errors.add(:container_path, "is already in use.") if is_parent
  end

  # Ensure we record the user.
  # Will not update if the deployment is null.
  def update_user
    self.user = self.deployment.user if self.deployment
  end

  def rebuild_services
    # Only if container_path or container_service change
    if self.saved_change_to_attribute?("container_path") || self.saved_change_to_attribute?("container_service_id")
      as = attached_services
      unless as[:known].empty?
        audit = if current_audit.nil?
                  Audit.create_from_object!(self, 'updated', '127.0.0.1')
                else
                  current_audit
                end
        as[:known].each do |i|
          PowerCycleContainerService.new(i, 'rebuild', audit)
        end
      end
    end
  end

  # Track when this volume went offline, for billing purposes.
  def set_detached
    if self.container_service.nil? && self.detached_at.nil?
      self.update_column(:detached_at, Time.now.utc)
    elsif self.container_service && !self.detached_at.nil?
      self.update_column(:detached_at, nil)
    end
  rescue
    # Ignore errors while we migrate.
  end

  # Update the subscription when we mark this to be deleted
  def update_subscription
    if self.saved_change_to_attribute?("to_trash") && self.subscription
      if self.to_trash
        self.subscription.update(
          active: false,
          details: {
            volume_name: self.name
          }
        )
      elsif !self.to_trash
        self.subscription.update_attribute :active, true
      end
    end
  end

  def ensure_can_trash!
    throw(:abort) unless can_trash?
  end

end
