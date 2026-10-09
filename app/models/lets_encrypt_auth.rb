# Lets Encrypt Domain Validation
#
# @!attribute id
#   @return [Integer]
# @!attribute domain
#   @return [String] actual domain name used for validation
# @!attribute token
#   @return [String] token used in URL to find auth (http auth)
# @!attribute content
#   @return [String] content to be presented to LetsEncrypt (http auth)
# @!attribute challenge_type
#   @return [String] either http or dns
# @!attribute record_name
#   @return [String] dns record name
# @!attribute record_type
#   @return [String] Either `TXT` or `CNAME`
# @!attribute record_content
#   @return [String] value for dns record
# @!attribute expires_at
#   @return [Date]
class LetsEncryptAuth < ApplicationRecord
  scope :sorted, -> { order(Arel.sql("domain ASC, expires_at DESC")) }
  scope :expired, -> { where Arel.sql(%(expires_at < '#{Time.now.iso8601}')) }

  # @return [Deployment::ContainerDomain]
  belongs_to :container_domain, class_name: "Deployment::ContainerDomain", foreign_key: "domain_id", optional: true

  # @return [LetsEncrypt]
  belongs_to :certificate, class_name: "LetsEncrypt", foreign_key: "lets_encrypt_id"

  # @return [LetsEncryptAccount]
  has_one :account, through: :certificate

  # @return [Boolean]
  def expired?
    expires_at.nil? ? true : expires_at <= Time.now
  end

  # Load balancer whose shared (wildcard) certificate this authorization is for.
  #
  # @return [LoadBalancer, nil]
  def load_balancer
    certificate.load_balancers.find_by("lower(load_balancers.domain) = ?", domain.to_s.downcase)
  end

  # DNS alias name to write the challenge into, when the domain is not hosted
  # on our DNS provider but an ACME DNS alias zone is configured.
  #
  # @return [String, nil]
  def dns_alias
    return nil unless Dns::Zone.find_covering(domain).nil?
    load_balancer&.acme_dns_alias
  end

  # A local zone covering the domain wins. Otherwise, fall back to the alias zone.
  #
  # The alias zone is matched by exact name, not by a suffix walk: the walk
  # returns the shortest match, so with `acme.example.com` delegated and
  # `example.com` also local, it would write the TXT into the parent zone,
  # below the delegation cut, where nobody would ever see it.
  #
  # @return [Dns::Zone, nil]
  def dns_zone
    z = Dns::Zone.find_covering(domain)
    return z unless z.nil?
    return nil if dns_alias.blank?
    Dns::Zone.find_by(name: Setting.le_dns_alias_zone)
  end

  # Fully qualified name of the DNS-01 challenge record we write.
  #
  # @return [String]
  def dns_record_fqdn
    dns_alias.presence || "#{record_name}.#{domain}"
  end
end
