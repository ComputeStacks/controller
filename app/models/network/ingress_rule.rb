##
# Ingress Rule
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
#
# @!attribute restrict_cf
#   @return [Boolean] Only allow CF to access this ingress rule.
#
# @!attribute backend_ssl
#   @return [Boolean] If true, HAProxy will connect to your container via SSL.
#
# @!attribute external_access
#   @return [Boolean] If true, external access to this ingress rule will be allowed.
#
# @!attribute port
#   @return [Integer] Internal port of container
#
# @!attribute [r] port_nat
#   @return [Integer] Generated NAT port
#
# @!attribute proto
#   @return [http,tcp,tls,udp] `tls` is only possible when `tcp_lb` is true.
#
# @!attribute tcp_proxy_opt
#   @return [none,send-proxy,send-proxy-v2,send-proxy-v2-ssl,send-proxy-v2-ssl-cn]
#
# @!attribute tcp_lb
#   @return [Boolean] False will use local iptable rules (NAT). `tls` is not possible.
#
# @!attribute region
#   @return [Region]
#
# @!attribute container_service
#   @return [Deployment::ContainerService]
# @!attribute internal_load_balancer
#   @return [Deployment::ContainerService]
#
class Network::IngressRule < ApplicationRecord

  include Auditable
  include IngressRules::LoadBalancerMetrics
  include IngressValidator

  scope :udp, -> { where proto: "udp" }
  scope :tcp, -> { where proto: "tcp" }
  scope :tls, -> { where proto: "tls" }
  scope :http, -> { where proto: "http" }
  scope :tcp_lb_rules, -> { where tcp_lb: true }
  scope :tcp_iptable_rules, -> { where tcp_lb: false }

  scope :nat, -> { where.not(port_nat: 0) }
  scope :lb, -> { where(external_access: true) }

  belongs_to :container_service,
             class_name: 'Deployment::ContainerService',
             optional: true # It may be an sftp container

  has_one :global_load_balancer, through: :container_service, source: :load_balancer

  belongs_to :load_balancer_rule,
             foreign_key: 'load_balancer_rule_id',
             class_name: 'Network::IngressRule',
             optional: true

  has_one :internal_load_balancer, through: :load_balancer_rule, source: :container_service

  belongs_to :sftp_container,
             class_name: 'Deployment::Sftp',
             optional: true

  belongs_to :parent_param,
             class_name: "ContainerImage::IngressParam",
             foreign_key: "ingress_param_id",
             optional: true

  belongs_to :region

  has_many :container_domains, class_name: 'Deployment::ContainerDomain', dependent: :destroy

  # If this is the load balancer, find our backend rules
  has_many :load_balanced_rules, class_name: 'Network::IngressRule', foreign_key: 'load_balancer_rule_id', dependent: :nullify
  has_many :load_balanced_domains, through: :load_balanced_rules, source: :container_domains

  # validate :has_valid_port

  validates :port_nat, uniqueness: { scope: [:region_id, :proto] }, unless: -> { port_nat.zero? }
  validates :port, uniqueness: { scope: [:container_service_id, :proto] }, if: -> { container_service }
  validates :port, uniqueness: { scope: [:sftp_container_id, :proto] }, if: -> { sftp_container }

  before_save :set_nat_port
  before_destroy :update_node_rules!

  attr_accessor :sys_no_reload,
                :no_provision_domain,
                :skip_metadata_refresh,
                :skip_policy_updates

  after_save :update_global_load_balancer!
  after_commit :reload_load_balancer!, unless: Proc.new { |i| i.sys_no_reload }
  after_destroy :reload_load_balancer!, unless: Proc.new { |i| i.sys_no_reload }
  after_save :provision_domain, unless: Proc.new { |i| i.no_provision_domain }
  after_save :refresh_metadata, unless: Proc.new { |i| i.skip_metadata_refresh }

  def csrn
    "csrn:caas:project:ingress:#{resource_name}:#{id}"
  end

  def resource_name
    "#{port}#{proto}"
  end

  def deployment
    return container_service.deployment if container_service
    return sftp_container.deployment if sftp_container
    nil
  end

  def public_network?
    return region.public_network? if region
    false
  end

  def lb_proxy_name
    Digest::MD5.hexdigest("#{container_service.name}#{id}") if container_service
  end

  def toggle_nat!
    if load_balancer_rule
      load_balancer_rule.toggle_nat!
    elsif proto == 'http'
      errors.add(:proto, 'Unable to create nat port for HTTP service. Please change to TCP.')
      false
    elsif port_nat.zero?
      update external_access: true
    elsif port_nat > 0
      update external_access: false
    else
      errors.add(:base, 'unknown state')
      false
    end
  end

  # Helper to load local domains, and domains that are being LB'd by this service.
  def global_container_domains
    return [] if container_service.nil?
    container_service.is_load_balancer ? (container_domains.active + load_balanced_domains.active) : container_domains.active
  end

  # Display current public port
  # This function takes into account any custom load balancers
  def public_port
    return load_balancer_rule.port_nat if load_balancer_rule
    port_nat
  end

  # @return [Boolean]
  def uses_iptables?
    return false unless external_access
    return false if port_nat.zero?
    proto == "udp" || (proto == "tcp" && !tcp_lb)
  end

  # @return [Boolean]
  def uses_global_lb?
    return false unless external_access
    return false if port_nat.zero?
    proto == "tls" || (proto == "tcp" && tcp_lb)
  end

  private

  # Set Nat Port
  #
  def set_nat_port
    if external_access && port_nat.zero? && %w(tcp tls udp).include?(proto)
      unless load_balancer_rule # Only for ingress rules attached to our global LB.
        if public_network?
          self.port_nat = port
        else

          ActiveRecord::Base.uncached do
            # If tcp or udp exists, share the port with each other.
            if %w(tcp udp).include? proto
              port_pair = nil
              port_pair = container_service.ingress_rules.find_by(proto: (proto == 'tcp' ? 'udp' : 'tcp'), port: port) if container_service
              port_pair = sftp_container.ingress_rules.find_by(proto: (proto == 'tcp' ? 'udp' : 'tcp'), port: port) if sftp_container
              if port_pair && !Network::IngressRule.where(proto: proto, port: port, region: region).exists?
                self.port_nat = port_pair.port_nat
              end
            end

            if port_nat.zero?
              ports_in_use = Network::IngressRule.where.not(port_nat: 0).where(region: region, proto: proto).pluck(:port_nat)
              # https://serverfault.com/questions/401040/maximizing-tcp-connections-on-haproxy-load-balancer
              # as stated, i guess linux will use 32k+ for connections
              p = rand(10000..30000) while p.nil? || ports_in_use.include?(p)
              self.port_nat = p
            end
          end

        end
      end
    elsif !external_access && !port_nat.zero?
      self.port_nat = 0
    end
  end

  def reload_load_balancer!
    return if saved_changes.empty?
    update_node_rules!
  end

  def update_node_rules!
    if internal_load_balancer
      internal_load_balancer.containers.each do |container|
        PowerCycleContainerService.new(container, 'restart', current_audit).perform
      end
    elsif global_load_balancer
      LoadBalancerServices::DeployConfigService.new(global_load_balancer).perform
    elsif external_access && container_service
      LoadBalancerServices::DeployConfigService.new(region.load_balancer).perform if region&.load_balancer
    end
    unless skip_policy_updates
      NetworkWorkers::ServicePolicyWorker.perform_async(container_service.id) if container_service
      NetworkWorkers::SftpPolicyWorker.perform_async(sftp_container.id) if sftp_container
    end
    if sftp_container
      NodeWorkers::ReloadIptableWorker.perform_async sftp_container.node&.to_global_id.uri
    elsif container_service
      container_service.nodes.each do |n|
        NodeWorkers::ReloadIptableWorker.perform_async n.to_global_id.uri
      end
    end
  end

  # Set related service load balancer based on load_balanced_type setting.
  def update_global_load_balancer!
    return if public_network?
    if external_access && (global_load_balancer.nil? && load_balancer_rule.nil?)
      lb = region.load_balancer
      return unless lb
      if container_service && container_service.load_balancer.nil?
        container_service.update_attribute(:load_balancer, lb)
      elsif sftp_container && sftp_container.load_balancer.nil?
        sftp_container.update_attribute(:load_balancer, lb)
      end
    end
  end

  def provision_domain
    return if proto == "udp"
    return unless container_service
    return if public_network?
    Deployment::ContainerDomain.create_system_domain!(container_service)
  end

  # def has_valid_port
  #   if container_service
  #     if id && Network::IngressRule.where(proto: proto, port: port, container_service: container_service).where.not(id: id).exists?
  #       errors.add(:port, 'is already in use')
  #     elsif id.nil? && Network::IngressRule.where(proto: proto, port: port, container_service: container_service).exists?
  #       errors.add(:port, 'is already in use')
  #     end
  #   elsif sftp_container
  #     if id && Network::IngressRule.where(proto: proto, port: port, sftp_container: sftp_container).where.not(id: id).exists?
  #       errors.add(:port, 'is already in use')
  #     elsif id.nil? && Network::IngressRule.where(proto: proto, port: port, sftp_container: sftp_container).exists?
  #       errors.add(:port, 'is already in use')
  #     end
  #   end
  # end

  def refresh_metadata
    return if deployment.nil?
    ProjectWorkers::RefreshMetadataWorker.perform_async deployment.id
  end

end
