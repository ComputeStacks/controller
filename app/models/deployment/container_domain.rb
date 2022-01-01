##
# Deployment Container Domain
#
# @!attribute [r] id
#   @return [Integer]
# @!attribute domain
#   @return [String]
# @!attribute header_hsts
#   @return [Boolean] Manually enables or disables HSTS headers. Automatically enabled with lets encrypt
# @!attribute is_sys
#   @return [Boolean] Setting to true will disable domain name validation
# @!attribute le_enabled
#   @return [Boolean]
# @!attribute le_ready
#   @return [Boolean]
# @!attribute le_ready_checked
#   @return [Date]
# @!attribute sys_no_reload
#   @return [Boolean] Setting to true will disable load balancer reload on update
class Deployment::ContainerDomain < ApplicationRecord

  include Auditable
  include Authorization::ContainerDomain
  include LeContainerDomain

  scope :sorted, -> { order(:domain) }
  scope :active, -> { where(enabled: true) }

  # @return [Array<Audit>]
  has_many :audits, -> { where(rel_model: 'Deployment::ContainerDomain') }, foreign_key: :rel_id, class_name: 'Audit', dependent: :nullify

  # @return [User]
  belongs_to :user

  # @return [IngressRule]
  belongs_to :ingress_rule, class_name: 'Network::IngressRule', optional: true

  # @return [Deployment::ContainerService]
  has_one :container_service, through: :ingress_rule

  # @return [Deployment]
  has_one :deployment, through: :container_service

  has_many :collaborators, through: :deployment

  # @return [Array<EventLog>]
  has_and_belongs_to_many :event_logs, foreign_key: 'deployment_container_domain_id'

  # @return [Array<EventLogDatum>]
  has_many :event_details, through: :event_logs

  attr_accessor :is_sys, :sys_no_reload

  validates :user, presence: true
  validates :domain, presence: true
  validates :domain, uniqueness: { case_sensitive: false }
  validate :validate_domain_name, on: :create, unless: Proc.new { is_sys }

  after_save :reload_load_balancer!, unless: Proc.new { sys_no_reload }
  before_destroy :reload_load_balancer!, unless: Proc.new { sys_no_reload }

  after_update :update_le_on_user_change

  def enable_hsts_header?
    header_hsts || le_active? || system_domain
  end

  def expected_dns_entries
    # expected to be an array
    pub = []
    return pub if container_service&.load_balancer.nil?
    pub << container_service.load_balancer.public_ip
    container_service.load_balancer.ipaddrs.where(role: 'public').each do |i|
      addr = i.ip_addr.to_s
      pub << addr unless pub.include?(addr)
    end
    pub
  end

  def force_ssl?
    system_domain || (le_enabled && lets_encrypt&.active?) || force_https
  end

  def self.create_system_domain!(service)
    return [] if service.public_network?
    sysd = Deployment::ContainerDomain.sys_domain(service.region).first
    return [] if sysd.nil?
    return [] if service.nil? || service.user.nil?
    domains = []
    service.ingress_rules.where(external_access: true).each do |ingress|
      next if ingress.container_domains.where(system_domain: true).exists?
      domains << ingress.container_domains.create!(
        domain: "#{service.name}#{ingress.id}.#{sysd}",
        system_domain: true,
        is_sys: true,
        sys_no_reload: true,
        user: service.user
      )
    end
    domains
  end

  def self.sys_domain(region = nil)
    if region.nil?
      LoadBalancer.all.map { |i| i.domain unless i.domain.blank? }
    else
      return [] if region.load_balancer.nil?
      [region.load_balancer.domain]
    end
  end

  private

  def reload_load_balancer!
    return true unless ingress_rule
    if ingress_rule.external_access
      if ingress_rule.load_balancer_rule
        # internal load balancer
        # @type [Deployment::ContainerService]
        lb_service = ingress_rule.load_balancer_rule&.container_service
        if lb_service
          lb_service.containers.each do |container|
            PowerCycleContainerService.new(container, 'restart', current_audit).perform
          end
        end
      elsif container_service&.load_balancer
        LoadBalancerServices::DeployConfigService.new(container_service.load_balancer).perform
      end
    end
  end

  def validate_domain_name
    sysd = Deployment::ContainerDomain.sys_domain
    is_reserved_domain = false
    sysd.each do |i|
      is_reserved_domain = true if self.domain =~ /#{i}/
    end
    errors.add(:domain, 'is a reserved domain name.') if is_reserved_domain
    errors.add(:domain, 'is an invalid domain.') unless Dns::Zone.valid_domain?(self.domain)
  end

  # If we update the user, check to see if the LE cert has moved to another user.
  # If it has, re-initialize LE.
  def update_le_on_user_change
    if self.saved_change_to_attribute?("user_id")
      if lets_encrypt && lets_encrypt_user && (lets_encrypt_user != self.user)
        LetsEncryptWorkers::ChangeDomainOwnerWorker.perform_in(5.minutes, id)
      end
    end
  end

end
