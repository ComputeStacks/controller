##
# LoadBalancer Addresses
#
# @!attribute [r] id
#   @return [Integer]
# @!attribute label
#   @return [String]
# @!attribute ip_addr
#   @return [String]
# @!attribute role
#   @return [connect,internal,public,proxy]
#
class LoadBalancerAddr < ApplicationRecord
  acts_as_taggable # Tags are used for CS maintained addresses

  include Auditable

  scope :cloudflare, -> { where(label: "Cloudflare") }

  belongs_to :load_balancer

  validates :ip_addr, presence: true
  validates :ip_addr, uniqueness: {scope: :load_balancer}

  ##
  # LoadBalancerAddr Roles
  #
  # Supports both ipv4 and ipv6.
  #
  # * connect: The ip this CP should connect to to install config. (/32 or /128 only)
  # * internal: The internal IP that the LB may connect from (used for calico policy). (/32 or /128 only)
  # * public: Public IP. Valid for LE. (/32 or /128 only)
  # * proxy: External proxy hitting this load balancer. Valid for LE. (/any network size)
  #
  validates :role, inclusion: {in: %w[connect internal public proxy]}

  # One declaration: a second after_commit naming the same method replaces the first.
  after_commit :recheck_domain, if: :recheck_domain?

  # validate :is_ipaddr
  validate :ip_network_size

  def is_ipv4?
    ip_addr&.ipv4?
  end

  def is_ipv6?
    ip_addr&.ipv6?
  end

  private

  # Only roles that LoadBalancer#full_public_ip_list reads (public and proxy)
  # can change the domain check; a connect/internal change must not re-check,
  # since a transient DNS failure would flip a valid domain.
  DOMAIN_CHECK_ROLES = %w[public proxy].freeze

  def recheck_domain?
    return DOMAIN_CHECK_ROLES.include?(role) if previously_new_record? || destroyed?
    return false unless saved_change_to_role? || saved_change_to_ip_addr?

    DOMAIN_CHECK_ROLES.include?(role) || DOMAIN_CHECK_ROLES.include?(role_before_last_save)
  end

  # A domain checked before its address existed stays invalid until re-checked.
  # Nothing to re-check when the load balancer itself is being destroyed.
  def recheck_domain
    lb = load_balancer
    return if lb.nil? || lb.destroyed? || !LoadBalancer.exists?(lb.id)
    lb.queue_domain_validation
  end

  def ip_network_size
    Rails.logger.debug "#{ip_addr.inspect} #{ip_addr.class}"
    if %w[connect internal public].include?(role)
      errors.add(:ip_addr, "must be /32 when used in role #{role}") if ip_addr.ipv4? && ip_addr.prefix != 32
      errors.add(:ip_addr, "must be /128 when used in role #{role}") if ip_addr.ipv6? && ip_addr.prefix != 128
    end
  rescue => e
    errors.add(:ip_addr, "fatal #{e.message}")
  end
end
