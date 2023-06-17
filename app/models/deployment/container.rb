##
# Container
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] name
#   @return [String]
#
# @!attribute [r] current_state
#   @return [migrating,starting,stopping,working,alert,resource_usage,online,offline,unhealthy]
#
# @!attribute status
#   pending,running,stopped,error,degraded
#   @return [String]
#
# @!attribute req_state
#   @return [running,stopped]
#
# @!attribute ip_address
#   @return [Network::Cidr]
#
# @!attribute network
#   @return [Network]
#
# @!attribute region
#   @return [Region]
#
# @!attribute service
#   @return [Deployment::ContainerService]
#
# @!attribute load_balancer
#   @return [LoadBalancer]
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute collaborators
#   @return [Array<User>]
#
# @!attribute domains
#   @return [Array<Deployment::ContainerDomain>]
#
# @!attribute subscription
#   @return [Subscription]
#
# @!attribute event_logs
#   @return [Array<EventLog>]
#
# @!attribute alert_notifications
#   @return [Array<AlertNotification>]
#
# @!attribute node
#   @return [Node]
#
# @!attribute location
#   @return [Location]
#
class Deployment::Container < ApplicationRecord

  include Auditable
  include Authorization::Container
  include Containerized
  include Containers::AppEvent
  include Containers::ContainerLogs
  include Containers::ContainerMetrics
  include Containers::ContainerNetworking
  include Containers::ContainerRuntime
  include Containers::ContainerSubscription
  include Containers::ContainerUsage
  include Containers::ContainerVariables
  include Containers::Monarx
  include Containers::PowerManager
  include Containers::StateManager
  include UrlPathFinder

  scope :active, -> { where(req_state: 'running') }
  scope :migrating, -> { where status: 'migrating' }
  scope :sorted, -> { order(:name) }

  has_one :ip_address, class_name: 'Network::Cidr', dependent: :destroy
  has_one :network, through: :ip_address

  belongs_to :service,
             class_name: 'Deployment::ContainerService',
             foreign_key: 'container_service_id'

  has_one :region, through: :service
  has_one :load_balancer, through: :service

  has_one :image_variant, through: :service
  has_one :container_image, through: :image_variant
  has_one :deployment, through: :service
  has_many :collaborators, through: :deployment
  has_many :domains, through: :service

  has_one :user, through: :deployment

  belongs_to :subscription, optional: true
  has_many :products, through: :subscription

  belongs_to :node, optional: true
  has_one :location, through: :region

  has_one :metric_client, through: :region
  has_one :log_client, through: :region
  has_many :volumes, through: :service

  has_and_belongs_to_many :event_logs, foreign_key: 'deployment_container_id'

  has_many :alert_notifications, dependent: :destroy, foreign_key: 'container_id'

  after_update_commit :update_service_resource

  after_create_commit :refresh_user_quota
  after_destroy :refresh_user_quota

  def csrn
    "csrn:caas:project:container:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if name.blank?
    name.strip
  end

  ##
  # Helper to determine if this container can migrate to a different node
  def can_migrate?
    # service.volumes.empty? || service.volumes.where.not(volume_backend: 'local').exists?
    !service.volumes.where(volume_backend: 'local').exists?
  end

  def can_delete_stopped?
    return false if service.override_autoremove || container_image.override_autoremove
    user.user_group.remove_stopped
  end

  # Temporary helpers
  def label
    service.label
  end

  def client
    return nil if self.node.nil?
    node.client(3)
  end
  ####

  def sftp_container
    return nil if container_image.nil?
    return nil if node.nil? || !container_image.enable_sftp
    if region.has_clustered_storage? || (service.volumes.empty? && service.can_scale?)
      deployment.sftp_containers.where("nodes.region_id in (?)", service.region.id).joins(:node).first
    else
      nodes = service.nodes.where(region: region).pluck(:id)
      deployment.sftp_containers.find_by("node_id IN (?)", nodes)
    end
  end

  private

  # Update Container Service with CPU & Memory
  #
  def update_service_resource
    watched_attr = Set[ 'cpu', 'memory' ]
    have_attr = previous_changes.keys.to_set
    if watched_attr.intersect?(have_attr)
      unless service.cpu == cpu && service.memory == memory
        service.update(
                   cpu: cpu,
                   memory: memory
        )
      end
    end
  end

  def refresh_user_quota
    user.current_quota(true) if user
  end

end
