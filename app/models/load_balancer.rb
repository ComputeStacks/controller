##
# Load Balancer for Availability Zone
#
# @!attribute [r] id
#   @return [Integer]
# @!attribute name
#   @return [String]
# @!attribute label
#   @return [String]
# @!attribute ext_ip
#   @return [String]
# @!attribute ext_config
#   @return [String] (default: `/etc/haproxy/haproxy.cfg`)
# @!attribute ext_reload_cmd
#   @return [String] (default: `bash -c 'if [[ -z $(pidof haproxy) ]]; then service haproxy start; else service haproxy reload; fi;'`)
# @!attribute public_ip
#   @return [String]
# @!attribute ext_cert_dir
#   @return [Integer] (default: `/ext/haproxy/certs`)
# @!attribute ext_dir
#   @return [String] (default: `/ext/haproxy`)
# @!attribute domain
#   @return [String]
# @!attribute domain_valid
#   @return [Boolean]
# @!attribute domain_valid_check
#   @return [Date]
# @!attribute job_status
#   @return [String]
# @!attribute job_performed
#   @return [Date]
# @!attribute cpus
#   @return [Integer] Requires restart of load balancer (default: 1)
# @!attribute maxconn
#   @return [Integer] (default: 100000)
# @!attribute maxconn_c
#   @return [Integer] (default: 200)
# @!attribute ssl_cache
#   @return [Integer] (default: 1000000)
# @!attribute direct_connect
#   @return [Boolean] Allow connecting directly to container even if it is not on the same node as the load balancer (default: true)
# @!attribute le
#   @return [Boolean] (default: false)
# @!attribute le_last_checked
#   @return [Date]
# @!attribute cert_encrypted
#   @return [String]
# @!attribute internal_ip
#   @return [Array]
# @!attribute proxy_cloudflare
#   @return [Boolean] (default: true)
# @!attribute g_timeout_connect
#   @return [String] (Default: 5s)
# @!attribute g_timeout_client
#   @return [String] (default: 150s)
# @!attribute g_timeout_server
#   @return [String] (default: 150s)
# @!attribute max_queue
#   @return [Integer] (default: 50)
# @!attribute external_ips
#   @return [Array]
# @!attribute internal_ips
#   @return [Array]
# @!attribute proto_alpn
#   @return [Boolean] (default: true)
# @!attribute proto_11
#   @return [Boolean] (default: true)
# @!attribute proto_20
#   @return [Boolean] (default: true)
# @!attribute proto_23
#   @return [Boolean] (default: false)
#
class LoadBalancer < ApplicationRecord

  include Auditable
  include LoadBalancers::CloudflareProxyAddresses

  # @!scope class
  # @return [Array<LoadBalancer>]
  scope :sorted, -> { order( Arel.sql("lower(name) DESC, lower(label) DESC")) }

  # @return [Region]
  belongs_to :region

  # @return [Array<Deployment::ContainerService>]
  has_many :container_services, class_name: 'Deployment::ContainerService', dependent: :restrict_with_exception

  # @return [Array<Deployment::Sftp>]
  has_many :sftp_containers, class_name: 'Deployment::Sftp', dependent: :restrict_with_exception

  # @return [Array<Deployment::Container>]
  has_many :containers, -> { distinct }, through: :container_services

  # @return [Array<Deployment>]
  has_many :deployments, -> { distinct }, through: :container_services

  # @return [Array<User>]
  has_many :users, -> { distinct }, through: :deployments

  # @return [LetsEncrypt]
  belongs_to :lets_encrypt, optional: true

  # @return [Array<EventLog>]
  has_and_belongs_to_many :event_logs, dependent: :nullify

  # @return [Array<EventLogDatum>]
  has_many :event_details, through: :event_logs

  # TODO: Migrate public_ip, ext_ip, internal_ip to ipaddrs.
  # @return [Array<LoadBalancerAddr>]
  has_many :ipaddrs, class_name: 'LoadBalancerAddr', foreign_key: 'load_balancer_id', dependent: :destroy


  validates :public_ip, presence: true
  validates :domain, presence: true
  validates :ext_ip, presence: true
  validates :cpus, numericality: { only_integer: true }
  validates :maxconn, numericality: { only_integer: true }
  validates :maxconn_c, numericality: { only_integer: true }
  validates :ssl_cache, numericality: { only_integer: true }

  validate :valid_custom_cert?

  before_create :set_defaults

  attr_accessor :internal_ips, :external_ips, :skip_validation

  after_save :trigger_domain_validation
  after_save :trigger_le_generation

  before_validation :set_ext_ip

  serialize :ext_ip, coder: JSON
  serialize :internal_ip, coder: JSON

  def ipv6_enabled?
    !region.has_clustered_networking?
  end

  # Determine if all the parameters have been met and we can deploy/activate this load balancer
  # @return [Boolean]
  def active?
    has_shared_cert? && domain_valid
  end

  # @return [Boolean]
  def has_ssl_certs?
    container_services.joins(:ssl_certificates).exists? || has_shared_cert?
  end

  # @return [Boolean]
  def has_shared_cert?
    lets_encrypt&.active? || !cert_encrypted.blank?
  end

  # Defaults to LetsEncrypt, otherwise uses custom
  def deployable_shared_certificate
    lets_encrypt&.active? ? lets_encrypt.certificate_bundle : shared_certificate
  end

  # returns decrypted certificate (not lets encrypt)
  def shared_certificate
    return nil if cert_encrypted.blank?
    Secret.decrypt!(cert_encrypted)
  rescue => e
    ExceptionAlertService.new(e, '5c64a85fcdce6202').perform
    nil
  end

  # Store user supplied certificate as encrypted (`cert_encrypted`)
  # The cert should include all components: cert, ca, and pkey.
  # @param data [String] unencrypted certificate
  # @return [String]
  def shared_certificate=(data)
    self.cert_encrypted = Secret.encrypt!(data)
  end

  # @return [Boolean]
  def has_custom_ssl?
    self.container_services.each do |i|
      return true unless i.ssl_certificates.empty?
    end
    false
  end

  # Returns the http kind string for HAProxy
  #
  # The order is important!
  def haproxy_http_proto
    # example: alpn h2,http/1.1
    ar = []
    ar << 'h2' if proto_20
    ar << 'http/1.1' if proto_11
    proto_alpn ? "alpn #{ar.join(',')}" : ar.join(',')
  end

  # Find a LB for a given node
  # @param node [Node]
  # @return [LoadBalancer]
  def self.find_by_node(node)
    return nil if node.nil?
    LoadBalancer.all.each do |lb|
      return lb if lb.ext_ip.include?(node.primary_ip)
      return lb if lb.internal_ip.include?(node.primary_ip)
    end
    nil
  end

  # Given an IP, is that pointing to this load balancer?
  # @param ip [String] ip address
  # @return [Boolean]
  def ip_allowed?(ip)
    is_allowed = false
    allowed_ips = full_public_ip_list
    allowed_ips.each do |i|
      range = i.to_range
      if range === ip
        is_allowed = true
        break
      end
    end
    is_allowed
  rescue
    false
  end

  ##
  # List all publicly allowed public ip addresses for this load balancer
  #
  # Currently only used by LetsEncrypt validation
  # This will *exclude* private IP addresses.
  # @return [Array]
  def full_public_ip_list
    allowed = []
    legacy_public_ip = IPAddr.new(public_ip)

    unless Rails.env.production? && legacy_public_ip.private?
      # Don't allow private IP's. Currently, this list is designed for validating domain names for LetsEncrypt
      allowed << legacy_public_ip
    end

    ipaddrs.where(role: 'proxy').each do |i|
      allowed << i.ip_addr unless i.ip_addr.private? || allowed.include?(i.ip_addr)
    end
    ipaddrs.where(role: 'public').each do |i|
      allowed << i.ip_addr unless i.ip_addr.private? || allowed.include?(i.ip_addr)
    end
    region.nodes.pluck(:public_ip).each do |i|
      begin
        ii = IPAddr.new(i)
        allowed << ii unless ii.private? || allowed.include?(ii)
      rescue => e
        ExceptionAlertService.new(e, 'd665c51f31b2e1ed').perform
        next
      end
    end
    allowed
  end

  # Create list for HAProxy config to accept forwarded IP header
  # @return [Array]
  def proxy_ipaddrs
    ips = []
    unless ext_ip.empty?
      ext_ip.each do |i|
        ip = IPAddr.new(i)
        ips << ip unless ips.include?(ip)
      end
    end
    unless internal_ip.empty?
      internal_ip.each do |i|
        ip = IPAddr.new(i)
        ips << ip unless ips.include?(ip)
      end
    end
    ipaddrs.where(role: 'proxy').each do |i|
      next if i.is_ipv6? # Temporary until we can support ipv6 on the nodes.
      ips << i.ip_addr unless ips.include?(i.ip_addr)
    end
    ips
  end

  # @return [Array]
  def cloudflare_ipaddrs
    ips = []
    ipaddrs.cloudflare.each do |i|
      next if i.is_ipv6? # Temporary until we can support ipv6 on the nodes.
      ips << i.ip_addr unless ips.include?(i.ip_addr)
    end
    ips
  end

  # List of domains required for this shared url.
  # Currently used by LetsEncrypt to order the certificate
  #
  # @return [Array]
  def dns_domains
    %W(#{domain} *.#{domain})
  end

  private

  def set_ext_ip
    unless self.external_ips.blank?
      self.ext_ip = self.external_ips.split(',').map {|i| i.strip}
    end
    unless self.internal_ips.blank?
      self.internal_ip = self.internal_ips.split(',').map {|i| i.strip}
    end
  end

  def set_defaults
    generated_name = NamesGenerator.name(0)
    self.name = generated_name
    self.label = generated_name if self.label.blank?
    self.ext_ip = [] if self.ext_ip.blank?
  end

  # Very basic validation...
  def valid_custom_cert?
    unless shared_certificate.blank?
      errors.add(:shared_certificate, "is an invalid certificate") unless OpenSSL::X509::Certificate.new(shared_certificate).serial.kind_of?(OpenSSL::BN)
    end
  rescue
    errors.add(:shared_certificate, "is an invalid certificate")
  end

  def trigger_domain_validation
    return if skip_validation
    if saved_change_to_attribute?("domain")
      LoadBalancerWorkers::ValidateDomainWorker.perform_async id, current_audit&.id
    end
  end

  def trigger_le_generation
    return if skip_validation
    if saved_change_to_attribute?("le")
      LoadBalancerServices::LetsEncryptService.new(self, current_audit).perform
    end
  end

end
