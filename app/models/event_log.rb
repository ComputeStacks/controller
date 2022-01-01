##
# EventLog
#
# @!attribute [r] id
#   @return [Integer]
# @!attribute locale
#   @return [String]
# @!attribute locale_keys
#   @return [Hash]
# @!attribute status
#   @return [String]
# @!attribute audit
#   @return [Audit]
# @!attribute event_code
#   `echo $(openssl rand -hex 8) | tr -d '\n' | pbcopy`
#   @return [String]
class EventLog < ApplicationRecord

  include Events::CodeState
  include Events::EventPurger
  include Events::StateManager

  # @!scope class
  # @return [Array<EventLog>]
  scope :sorted, -> { order(created_at: :desc) }

  # @!scope class
  # @return [Array<EventLog>]
  scope :recent, -> { where Arel.sql %Q( event_logs.updated_at > '#{1.day.ago.iso8601}' ) }

  # @return [Array<AlertNotification>]
  has_and_belongs_to_many :alert_notifications

  # @return [Array<Deployment::Container>]
  has_and_belongs_to_many :containers, class_name: 'Deployment::Container', association_foreign_key: 'deployment_container_id'

  # @return [Array<Deployment::ContainerDomain>]
  has_and_belongs_to_many :container_domains, class_name: 'Deployment::ContainerDomain', association_foreign_key: 'deployment_container_domain_id'

  # @return [Array<ContainerRegistry>]
  has_and_belongs_to_many :container_registries

  # @return [Array<Deployment::ContainerService>]
  has_and_belongs_to_many :container_services, class_name: 'Deployment::ContainerService', association_foreign_key: 'deployment_container_service_id'

  # @return [Array<Deployment>]
  has_and_belongs_to_many :deployments

  # @return [Array<LetsEncrypt>]
  has_and_belongs_to_many :lets_encrypts

  # @return [Array<LoadBalancer>]
  has_and_belongs_to_many :load_balancers

  # @return [Array<Node>]
  has_and_belongs_to_many :nodes

  # @return [Array<Deployment::Sftp>]
  has_and_belongs_to_many :sftp_containers, class_name: 'Deployment::Sftp', association_foreign_key: 'deployment_sftp_id'

  # @return [Array<User>]
  has_and_belongs_to_many :users

  # @return [Array<Volume>]
  has_and_belongs_to_many :volumes

  # @return [Audit]
  belongs_to :audit, optional: true

  # @return [Array<SystemEvent>]
  has_many :system_events, through: :audit

  # @return [Array<EventLogDatum>]
  has_many :event_details, class_name: 'EventLogDatum', dependent: :destroy

  accepts_nested_attributes_for :event_details

  # Return an array of all related associations.
  #
  # @param [User] current_user
  # @return [Array<User>]
  def subscribers(current_user)
    subs = containers + container_domains + container_registries + container_services + deployments + sftp_containers + volumes
    current_user.is_admin ? (subs + lets_encrypts + load_balancers + users + nodes) : subs
  end

  # Find a Event and validate the user has permission to access it
  #
  # @param [Integer] id
  # @param [User] user
  # @return [EventLog]
  def self.find_for_user(id, user)
    event = find_by(id: id)
    return nil if event.nil?
    return event if user.is_admin
    return event if event.audit&.user == user # User performed the action

    # check if event deployment id's exist in the user's deployment list array
    return event unless (event.deployments.pluck(:id) & Deployment.find_all_for(user).pluck(:id)).empty?

    nil
  end

  def ref_obj
    # return self.deployed_container unless self.deployed_container.nil?
    # return self.load_balancer unless self.load_balancer.nil?
    # return self.volume if self.volume
    nil
  end

  # @return [String]
  def table_class
    if notice
      case status
      when 'warning'
        'warning'
      when 'alert'
        'danger'
      else
        ''
      end
    end
  end

  # @return [String]
  def description
    I18n.t("events.messages.#{locale}", locale_keys.symbolize_keys)
  rescue
    "#{locale} #{locale_keys}"
  end

end
