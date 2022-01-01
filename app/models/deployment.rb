##
# Deployment
#
# TODO: Rename to 'Project'.
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute name
#   @return [String]
#
# @!attribute current_state
#   @return [working,deleting,alert,ok]
#
# @!attribute skip_ssh
#   @return [Boolean] If true, no sftp container will be provisioned.
#
# @!attribute token
#   @return [String] UUID
#
# @!attribute user
#   @return [User]
#
# @!attribute services
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute load_balancers
#   @return [Array<Deployment::ContainerService>]
#
# @!attribute container_images
#   @return [Array<ContainerImage>]
#
# @!attribute ingress_rules
#   @return [Array<Network::IngressRule>]
#
# @!attribute setting_params
#   @return [Array<ContainerService::SettingConfig>]
#
# @!attribute networks
#   @return [Array<Network>]
#
# @!attribute volumes
#   @return [Array<Volume>]
#
# @!attribute ssl_certificates
#   @return [Array<Deployment::Ssl>]
#
# @!attribute deployed_containers
#   @return [Array<Deployment::Container>]
#
# @!attribute domains
#   @return [Array<Deployment::ContainerDomain>]
#
# @!attribute nodes
#   @return [Array<Node>]
#
# @!attribute subscriptions
#   @return [Array<Subscription>]
#
# @!attribute sftp_containers
#   @return [Array<Deployment::Sftp>]
#
# @!attribute event_logs
#   @return [Array<EventLog>]
#
# @!attribute orders
#   @return [Array<Order>]
#
# @!attribute project_notifiers
#   @return [Array<ProjectNotification>]
#
# @!attribute alert_notifications
#   @return [Array<AlertNotification>]
#
# @!attribute deployment_collaborators
#   @return [Array<DeploymentCollaborator>]
#
# @!attribute collaborators
#   @return [Array<User>]
#
# @!attribute project_ssh_keys
#   @return [Array<Deployment::SshKey>]
#
# @!attribute created_at
#   @return [DateTime]
#
# @!attribute updated_at
#   @return [DateTime]
#
class Deployment < ApplicationRecord
  acts_as_taggable

  include Auditable
  include Authorization::Deployment
  include Projects::CalicoProjectPolicy
  include Projects::ProjectLogs
  include Projects::ProjectHealth
  include Projects::ProjectMetrics
  include Projects::ProjectOwnership
  include Projects::StateManager
  include UrlPathFinder

  scope :sorted, -> { order(created_at: :desc) }
  scope :sort_by_name, -> { order(:name) }

  belongs_to :user
  has_many :services, class_name: 'Deployment::ContainerService', dependent: :destroy
  has_many :load_balancers, -> { distinct }, through: :services
  has_many :ingress_rules, through: :services
  has_many :container_images, through: :services
  has_many :setting_params, through: :services
  has_many :networks, -> { distinct }, through: :services


  has_many :volumes, through: :services
  has_many :ssl_certificates, through: :services

  has_many :deployed_containers, through: :services, source: :containers
  has_many :domains, through: :services

  # has_many :container_params, through: :services

  has_many :nodes, -> { distinct }, through: :deployed_containers

  has_many :subscriptions, through: :deployed_containers

  has_many :shared_nodes, -> { distinct }, through: :deployed_containers, source: :node

  has_many :regions, -> { distinct }, through: :deployed_containers, source: :region
  has_many :locations, -> { distinct }, through: :regions

  has_many :orders, dependent: :nullify

  # has_many :logs, class_name: "Deployment::EventLog", foreign_key: "deployment_id", dependent: :destroy
  has_and_belongs_to_many :event_logs

  has_many :sftp_containers, class_name: 'Deployment::Sftp', dependent: :nullify

  has_many :project_notifiers, class_name: 'ProjectNotification', dependent: :destroy
  # has_many :notification_rules, class_name: 'Deployment::NotificationRule', dependent: :destroy
  has_many :alert_notifications, through: :deployed_containers

  has_many :deployment_collaborators
  has_many :collaborators, through: :deployment_collaborators

  has_many :project_ssh_keys, class_name: 'Deployment::SshKey'

  before_destroy :cleanup_deployment

  before_destroy :clean_collaborators # This must be BEFORE collaborators are defined

  validates :name, presence: true

  before_create :set_token

  # Projects will be limited to a single region going forward.
  def region
    regions[0]
  end

  def uses_public_net?
    networks.where(is_public: true).exists?
  end

  ##
  # Are we using clustered storage?
  #
  # This is a helper to help use determine if we should
  # display HA messages to the user for this project.
  def has_clustered_storage?
    !regions.local_storage.exists?
  end

  def can_migrate?
    !volumes.all_local.exists?
  end

  def update_name!(name)
    return false if name.blank? || name.nil?
    return false unless self.update_attribute :name, name
    true
  end

  # Locations available for this deployment.
  def available_locations
    cr_nets = Location.where("networks.id IN (?)", self.networks.pluck(:id)).joins(:networks)
    cr_nets.empty? ? self.locations : cr_nets
  end

  def image_icons(clear_cache = false)
    cache_key = "proj_icons_#{self.id}"
    Rails.cache.fetch(cache_key, force: clear_cache, expires: 6.hours) do
      container_images.where(is_load_balancer: false).order(:name).distinct
    end
  end

  def content_variables
    {
      "user" => user.full_name,
      "project" => name
    }
  end

  private

  def set_token
    self.token = SecureRandom.uuid
  end

  def cleanup_deployment
    LoadBalancerServices::DeployConfigService.new.perform
  end

  def clean_collaborators
    return if deployment_collaborators.empty?
    if user_performer.nil?
      errors.add(:base, "Missing user performing delete action.")
      return
    end
    deployment_collaborators.each do |i|
      i.current_user = user_performer
      unless i.destroy
        errors.add(:base, %Q(Error deleting collaborator #{i.id} - #{i.errors.full_messages.join("\n")}))
      end
    end
  end

end
