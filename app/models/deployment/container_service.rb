##
# Container Service
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] is_load_balancer
#   @return [Boolean]
#
# @!attribute container_image
#   @return [ContainerImage]
#
# @!attribute [r] has_domain_management
#   @return [Boolean]
#
# @!attribute label
#   @return [String]
#
# @!attribute [r] name
#   @return [String]
#
# @!attribute master_domain
#   @return [Deployment::ContainerDomain]
#
# @!attribute [r] current_state
#   @return [working,alert,active_alert,offline_containers,resource_usage,online,inactive]
#
# @!attribute labels
#   @return [Hash]
#
# @!attribute has_sftp
#   @return [Boolean]
#
# @!attribute auto_scale
#   @return [Boolean]
#
# @!attribute auto_scale_horizontal
#   @return [Boolean]
#
# @!attribute auto_scale_max
#   @return [Decimal] Total max price (per-hour) that this service can be scaled to. 0.0 = no max.
#
# @!attribute product
#   @return [Product]
#
# @!attribute deployment
#   @return [Deployment]
#
# @!attribute containers
#   @return [Array<Deployment::Container>]
#
# @!attribute volumes
#   @return [Array<Volume>]
#
# @!attribute metric_client
#   @return [MetricClient]
#
# @!attribute log_client
#   @return [LogClient]
#
# @!attribute nodes
#   @return [Array<Node>]
#
# @!attribute location
#   @return [Location]
#
# @!attribute env_params
#   @return [Array<ContainerService::EnvConfig>]
#
# @!attribute setting_params
#   @return [Array<ContainerService::SettingConfig>]
#
# @!attribute subscriptions
#   @return [Array<Subscription>]
#
# @!attribute ssl_certificates
#   @return [Array<Deployment::Ssl>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
# @!attribute user
#   @return [User]
#
# @!attribute region
#   @return [Region]
#
#
class Deployment::ContainerService < ApplicationRecord
  acts_as_taggable

  include Auditable
  include Authorization::ContainerService
  include ContainerServices::CalicoServicePolicy
  include ContainerServices::NodeSelector
  include ContainerServices::ServiceConfig
  include ContainerServices::ServiceIngress
  include ContainerServices::ServiceLogs
  include ContainerServices::ServiceMetrics
  include ContainerServices::ServiceUsage
  include ContainerServices::StateManager
  include ContainerServices::Wordpress

  scope :sorted, -> { order(:label) }
  scope :web_only, -> { where(network_ingress_rules: { external_access: true, proto: 'http' }).joins(:ingress_rules).distinct }
  scope :load_balancers, -> { where(is_load_balancer: true) }

  belongs_to :container_image
  belongs_to :deployment
  belongs_to :region
  belongs_to :master_domain, class_name: 'Deployment::ContainerDomain', optional: true

  has_one :user, through: :deployment
  has_many :collaborators, through: :deployment

  belongs_to :initial_subscription, class_name: 'Subscription', optional: true

  has_many :ssl_certificates,
       class_name: 'Deployment::Ssl',
       dependent:  :destroy

  has_many :containers,
       class_name: 'Deployment::Container',
       dependent:  :destroy

  has_many :subscriptions, through: :containers
  has_many :networks, -> { distinct }, through: :containers

  has_many :env_params,
       class_name:  'ContainerService::EnvConfig',
       foreign_key: 'container_service_id',
       dependent:   :destroy

  has_many :setting_params,
       class_name:  'ContainerService::SettingConfig',
       foreign_key: 'container_service_id',
       dependent:   :destroy

  has_many :volume_maps
  has_many :volumes, through: :volume_maps

  has_many :secrets, -> { where(rel_model: 'Deployment::ContainerService') }, foreign_key: 'rel_id', dependent: :destroy

  has_one :metric_client, through: :region
  has_one :log_client, through: :region

  has_many :nodes, -> { distinct }, through: :containers

  has_one :location, through: :region

  # has_many :logs, class_name: 'Deployment::EventLog', dependent: :destroy, foreign_key: 'service_id'
  has_and_belongs_to_many :event_logs, foreign_key: 'deployment_container_service_id'

  # Container Links
  has_many :links, class_name: 'Deployment::ContainerLink', foreign_key: 'service_id', dependent: :destroy
  has_many :service_resources, through: :links, source: :service_resource

  has_many :alert_notifications, through: :containers

  has_many :dependent_links,
       class_name:  'Deployment::ContainerLink',
       foreign_key: 'service_resource_id',
       dependent:   :destroy

  has_many :dependent_services, through: :dependent_links, source: :service

  before_destroy :flag_volumes

  def csrn
    "csrn:caas:project:service:#{resource_name}:#{id}"
  end

  def resource_name
    return "null" if name.blank?
    name.strip
  end

  def can_scale?
    !public_network? && container_image.can_scale
  end

  def current_load_balancer
    return load_balancer if load_balancer
    ingress_rules.joins(:load_balancer_rule).empty? ? nil : ingress_rules.joins(:load_balancer_rule).first.internal_load_balancer
  end

  def can_migrate?
    !volumes.all_local.exists?
  end

  def uses_load_balancer?
    ingress_rules.where(external_access: true).exists?
  end

  def has_domain_management
    ingress_rules.where(proto: 'http').exists?
  end

  def requires_sftp_containers?
    volumes.where(enable_sftp: true).exists?
  end

  # Helpers
  def label_with_id
    "#{id}-#{label}"
  end

  def package
    return initial_subscription.package if initial_subscription
    return nil if subscriptions.empty?
    subscriptions.first.package
  end

  # Used to place within cluster
  def package_for_node
    return initial_subscription.package if initial_subscription
    return BillingPackage.new(cpu: 1, memory: 512) if containers.empty?
    containers.first.package_for_node
  end

  # Grab the oldest, active, subscription.
  #
  def subscription
    subscriptions.all_active.order(created_at: :asc).first
  end

  ##
  # Find and return the most recent event
  def last_event
    event_logs.select(:id, :created_at, :updated_at).sorted.limit(1).first.updated_at
  rescue
    nil
  end

  # Default URL
  #
  # Priority:
  # * master domain
  # * http
  # * tls
  # * tcp
  def default_domain
    d = master_domain
    # Order by port to give higher pref to lower port
    # the idea is that `80` will be selected first over something like `7080`.
    d = domains.where(
      system_domain:         true,
      network_ingress_rules: {
        proto:           'http',
        external_access: true
      }
    ).joins(:ingress_rule).order( Arel.sql("network_ingress_rules.port")).limit(1).first if d.nil?
    d = domains.where(
      system_domain:         true,
      network_ingress_rules: {
        proto:           'tls',
        external_access: true
      }
    ).joins(:ingress_rule).limit(1).first if d.nil?
    d = domains.where(
      system_domain:         true,
      network_ingress_rules: {
        proto:           'tcp',
        external_access: true
      }
    ).joins(:ingress_rule).limit(1).first if d.nil?
    d.nil? ? nil : d.domain
  end

  def sftp_containers
    if requires_sftp_containers?
      sftps = []
      self.containers.each do |i|
        s = i.sftp_container
        next if s.nil?
        sftps << s unless sftps.include?(s)
      end
      sftps
    else # For all others, we just pick one!
      deployment.sftp_containers.exists? ? [ deployment.sftp_containers.first ] : []
    end
  end

  def content_variables
    container_ar = []
    containers.each do |c|
      container_ar << {
        'name' => c.name,
        'ip' =>  c.local_ip
      }
    end
    {
      'default_domain' => default_domain,
      'ingress_rules' => ingress_rules.map(&:attributes),
      'containers' => container_ar
    }
  end

  private

  def flag_volumes
    volumes.each do |i|
      i.to_trash = true
      i.trashed_by = current_audit if current_audit
      unless i.save
        Rails.logger.warn "[VOL] #{i.errors.full_messages.inspect}"
      end
    end
  end

end
