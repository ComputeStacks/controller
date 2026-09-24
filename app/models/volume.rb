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
# @!attribute user
#   @return [User]
##
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
# @!attribute awaiting_mount
#   @return [Boolean] The row, its VolumeMap and the docker volume exist, but no container
#     has been created with the bind yet. See the `awaiting_mount` scope below.
#
# @!attribute borg_freq
#   @return [String] A cron string
#
# @!attribute borg_strategy
#   custom file mariadb mysql postgres
#   @return [String]
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
# @!attribute container_services
#   @return [Array<Deployment::ContainerService>]
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
  # "Reachable over SFTP", which is what every caller of this scope means — the exporters that
  # write FileZilla/Transmit bookmarks, and the SFTP help panel that tells a customer their
  # paths. `awaiting_mount` volumes are excluded for the same reason
  # `Containers::SshVolumes#volumes` excludes them: the SFTP container will not mount one, so a
  # bookmark or a documented path pointing at it leads nowhere.
  scope :sftp_enabled, -> { where(enable_sftp: true, awaiting_mount: false) }
  scope :all_local, -> { where(volume_backend: "local") }

  # Volumes whose bind has not landed in a container yet.
  #
  # `awaiting_mount` means: this row, its VolumeMap and the real docker volume on the node
  # ALL exist, but no container has ever been created carrying the bind — so the mount is
  # not present inside any running container. Docker bakes binds at container-create time,
  # so a volume attached to an already-deployed service stays in this state until that
  # service's next natural rebuild (we deliberately do not rebuild or restart anything).
  #
  # While it is true, the volume is empty and unreachable from the application, so:
  #   * the agent is told `backup: false` (see Volumes::ConsulVolume#default_consul_data) —
  #     otherwise borg builds a healthy-looking archive series containing none of the
  #     customer's data;
  #   * manual backup and restore are refused;
  #   * it is not offered as a clone source (ContainerImage::VolumeParam#available_to_clone);
  #   * it is not exposed over SFTP (Containers::SshVolumes#volumes) — a customer must never
  #     be able to upload into a volume their app cannot see and that has backups suppressed.
  #
  # The flag is cleared by the mount detector when a container is actually built with the
  # bind; nothing else should write it.
  scope :awaiting_mount, -> { where(awaiting_mount: true) }

  has_many :volume_maps, dependent: :destroy

  # `:nullify`, never `:destroy`: a cascade would delete the clone job — and with it
  # owns_snapshot/clone_label — while the temporary borg archive still sits in the SOURCE
  # volume's repo, leaking it permanently. See VolumeCloneJob.
  has_one :volume_clone_job, dependent: :nullify
  has_many :source_clone_jobs, class_name: "VolumeCloneJob", foreign_key: :source_volume_id,
    dependent: :nullify
  has_many :container_services, through: :volume_maps
  has_many :containers, through: :volume_maps
  belongs_to :deployment, optional: true
  # belongs_to :container_service, class_name: 'Deployment::ContainerService', optional: true
  # has_one :deployment, through: :container_service
  # has_many :containers, through: :container_service

  belongs_to :template, class_name: "ContainerImage::VolumeParam", optional: true

  has_many :collaborators, through: :deployment

  belongs_to :region, optional: true # optional is temporary while we transition.
  has_one :location, through: :region
  belongs_to :user, optional: true
  has_one :user_group, through: :user
  has_and_belongs_to_many :nodes

  # has_many :logs, class_name: 'Deployment::EventLog', dependent: :nullify
  has_and_belongs_to_many :event_logs
  has_many :audits, -> { where(rel_model: "Volume") }, foreign_key: :rel_id, class_name: "Audit", dependent: :nullify

  belongs_to :subscription, optional: true

  validates :label, presence: true

  before_validation :set_name, on: :create

  before_save :set_trash_after # , if: :persisted?
  before_save :update_user, unless: :skip_user_update
  # after_save :rebuild_services, if: :force_rebuild

  after_save :update_subscription

  after_commit :set_detached
  # Only on create/update — NOT destroy. `volume.destroy`'s teardown issues a DELETE to the
  # agent (TrashVolumeService); a destroy-time re-PUT would re-add a `trash:true` desired-state
  # row after that DELETE and loop teardown.
  after_commit :update_consul!, on: [:create, :update]

  validates :name, presence: true, uniqueness: true

  belongs_to :trashed_by, class_name: "Audit", optional: true

  before_destroy :ensure_can_trash!

  # CurrentAudit: Audit in use for this job.
  # ProvisionVolume: Build the volume on the node
  # ForceRebuild: Useful after changes are made to the container service.
  # attr_accessor :force_rebuild, :skip_user_update
  attr_accessor :skip_user_update

  # @return [Deployment::ContainerService]
  def owner
    volume_maps.find_by(is_owner: true)&.container_service
  end

  def csrn
    "csrn:caas:project:vol:#{resource_name}:#{id}"
  end

  # The agent-facing project_id. A detached volume (no deployment) maps null→the reserved
  # sentinel 0 (Deployment ids are ≥1, so it can't collide). Applied consistently in the
  # volume PUT URL path, the task POST body, and the volume desired-state `project_id` — the
  # three must agree or the agent's scheduled-backup task project_id diverges. Use `.to_s` at
  # HTTP call sites.
  # @return [Integer]
  def agent_project_id
    deployment&.id || 0
  end

  def resource_name
    return "null" if label.blank?
    label.strip.downcase.gsub(/[^a-z0-9\s]/i, "").tr(" ", "_")[0..10]
  end

  # Pick the primary container service
  def container_service
    volume_maps.primary.first&.container_service
  end

  def can_trash?
    to_trash && trash_after <= Time.now
  end

  def operation_in_progress?
    event_logs.running.where.not(event_code: EventLog.non_blocking_codes).exists?
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
      update_column :region_id, nodes.first.region&.id
    end
    nodes.available.each do |i|
      i.list_all_containers.each do |c|
        c.info["Mounts"].each do |m|
          if m["Name"] == name
            cname = c.info["Names"].first.split("/").last
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
    ExceptionAlertService.new(e, "cf7db317de13af0c").perform
    SystemEvent.create!(
      message: "Error loading volume services #{id}.",
      log_level: "warn",
      data: {
        volume: {
          id: id,
          name: name,
          user: user&.id
        },
        errors: e.message
      },
      event_code: "cf7db317de13af0c"
    )
    nil
  end

  def find_node
    if !nodes.empty?
      nodes.first
    elsif deployment
      deployment.nodes.first
    elsif region
      region.nodes.available.first
    end
  end

  class << self
    # Exclude this volume from SFTP containers for specific roles.
    def excluded_roles
      db_roles + %w[pma]
    end

    # This is considered a database volumes for the following roles
    def db_roles
      %w[mysql postgres mariadb postgresql percona pg]
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
    self.name = SecureRandom.uuid.strip if name.blank?
  end

  # Ensure we record the user.
  # Will not update if the deployment is null.
  def update_user
    self.user = deployment.user if deployment
  end

  # Track when this volume went offline, for billing purposes.
  def set_detached
    if container_services.empty? && detached_at.nil?
      update detached_at: Time.now.utc
    elsif !container_services.empty? && !detached_at.nil?
      update detached_at: nil
    end
  rescue
    # Ignore errors while we migrate.
  end

  # Update the subscription when we mark this to be deleted
  def update_subscription
    if saved_change_to_attribute?("to_trash") && subscription
      if to_trash
        subscription.update(
          active: false,
          details: {
            volume_name: name
          }
        )
      elsif !to_trash
        subscription.update active: true
      end
    end
  end

  def ensure_can_trash!
    throw(:abort) unless can_trash?
  end
end
