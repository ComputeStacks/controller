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

  scope :sorted, -> { order( Arel.sql("domain ASC, expires_at DESC") ) }
  scope :expired, -> { where Arel.sql(%Q(expires_at < '#{Time.now.iso8601}')) }

  # @return [Deployment::ContainerDomain]
  belongs_to :container_domain, class_name: 'Deployment::ContainerDomain', foreign_key: 'domain_id', optional: true

  # @return [LetsEncrypt]
  belongs_to :certificate, class_name: 'LetsEncrypt', foreign_key: 'lets_encrypt_id'

  # @return [LetsEncryptAccount]
  has_one :account, through: :certificate


  # @return [Boolean]
  def expired?
    expires_at.nil? ? true : expires_at <= Time.now
  end

  # @return [Dns::Zone]
  def dns_zone
    # Allow a few extra levels.
    i = 2
    count = 4
    z = nil
    loop do
      tld = domain.split('.').last(i)
      z = Dns::Zone.find_by(name: tld.join('.'))
      break unless z.nil?
      break if i > count
      i += 1
    end
    z
  end

end
