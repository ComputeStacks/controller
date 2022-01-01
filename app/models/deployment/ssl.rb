##
# Deployment SSL
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute [r] cert_serial
#   Stored when saving `crt`.
#   @return [String]
#
# @!attribute [r] issuer
#   Stored when saving `crt`.
#   @return [String]
#
# @!attribute [r] subject
#   Stored when saving `crt`.
#   @return [String]
#
# @!attribute [r] not_before
#   Stored when saving `crt`.
#   @return [DateTime]
#
# @!attribute [r] not_after
#   Stored when saving `crt`.
#   @return [DateTime]
#
# @!attribute crt
#   @return [String]
#
# @!attribute pkey
#   @return [String]
#
class Deployment::Ssl < ApplicationRecord

  include Auditable

  belongs_to :container_service, class_name: 'Deployment::ContainerService', foreign_key: 'container_service_id'
  has_one :deployment, through: :container_service

  validates :cert_serial, uniqueness: true
  validates :crt, presence: true, on: :create
  validates :pkey, presence: true, on: :create
  validate :validate_certificate, on: :create
  before_create :store_cert_info

  after_create_commit :reload_lb

  ##
  # Presentation Helpers
  def formatted_subject
    subject.split("CN=").last
  rescue
    subject
  end

  def formatted_issuer
    issuer.split("CN=").last
  rescue
    issuer
  end

  def pkey
    return nil if pkey_encrypted.blank?
    Secret.decrypt!(pkey_encrypted)
  end

  def pkey=(data)
    self.pkey_encrypted = Secret.encrypt!(data)
  end

  def certificate_bundle
    return pkey if crt.blank? # Legacy certs only store the combined bundle in the `pkey_encrypted field`
    combined = []
    combined << crt
    combined << ca unless ca.blank?
    combined << pkey
    combined.join('\\n')
  end

  private

  def reload_lb
    if container_service&.load_balancer
      LoadBalancerServices::DeployConfigService.new(container_service.load_balancer).perform
    end
  end

  def store_cert_info
    crt_check = OpenSSL::X509::Certificate.new(crt)
    self.not_before = crt_check.not_before
    self.not_after = crt_check.not_after
    self.cert_serial = crt_check.serial.to_s
    self.issuer = crt_check.issuer.to_s
    self.subject = crt_check.subject
  end

  ##
  # Validate Certificates
  #
  # * Using OpenSSL to load the certificates; will raise exception if invalid.
  # * Validate certificate belongs to private key, and vice versa.
  def validate_certificate
    # Check if private & certificate are valid keys.
    key_check = if pkey[0..29] == '-----BEGIN EC PRIVATE KEY-----'
      OpenSSL::PKey::EC.new pkey
    else
      OpenSSL::PKey::RSA.new pkey
    end
    errors.add(:base, "Not a valid private key") if key_check.nil? || !key_check.private?
    crt_check = OpenSSL::X509::Certificate.new(crt)
    errors.add(:base, "Not a valid public key") if crt_check.nil? || !crt_check.serial.kind_of?(OpenSSL::BN)
    unless crt_check.check_private_key(key_check)
      errors.add(:base, "Private key does not match supplied certificate.")
    end
    unless ca.blank?
      ca_check = OpenSSL::X509::Certificate.new(ca)
      errors.add(:base, "Invalid CA Certificate") if ca_check.nil? || !ca_check.serial.kind_of?(OpenSSL::BN)
      if crt_check
        unless crt_check.verify(ca_check.public_key)
          errors.add(:base, "Certificate is not signed by the supplied CA certificate")
        end
      end
    end
  rescue
    errors.add(:base, "Not a valid certificate")
  end

end
