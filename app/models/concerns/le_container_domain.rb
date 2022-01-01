# @!method lets_encryptable
#   @!scope class
#   @return [Array<Deployment::ContainerDomain>] Active, non-system, domains with `le_enabled`
# @!attribute lets_encrypt
#   @return [LetsEncrypt]
# @!attribute lets_encrypt_user
#   @return [User]
# @!attribute skip_validation
#   @return [Boolean] Setting this to true will skip validation and set it to valid. (only if `le_enabled` is true)
module LeContainerDomain
  extend ActiveSupport::Concern

  included do
    scope :lets_encryptable, -> { where(system_domain: false, le_enabled: true, enabled: true) }

    scope :lets_encrypt_ready, -> { where(le_enabled: true, enabled: true, le_ready: true) }

    belongs_to :lets_encrypt, optional: true

    has_one :lets_encrypt_user, through: :lets_encrypt, source: :user

    before_save :disable_le_ready, unless: Proc.new { le_enabled }

    after_save :validate_le_domain, if: Proc.new { le_enabled }
    after_save :lets_encrypt_init!, if: Proc.new { le_ready }
    after_save :clean_lets_encrypt, unless: Proc.new { le_ready }

    attr_accessor :skip_validation
  end

  # Determines if LetsEncrypt is active for this domain
  def le_active?
    return false if system_domain || !le_enabled || !le_ready
    return false if lets_encrypt.nil?
    lets_encrypt.names.include?(domain) && lets_encrypt.active?
  end

  # Determines if we still need to verify this domain
  def le_require_verify?
    le_enabled && !le_ready
  end


  # Determine if DNS IP is allowed.
  # @param value [IPAddr]
  # @return [Boolean]
  def le_dns_allowed?(value)
    lb = container_service.load_balancer
    return nil if lb.nil?
    lb.ip_allowed? value
  rescue
    false
  end

  private

  # @return [Boolean]
  def lets_encrypt_init!
    return true if lets_encrypt
    return false unless le_ready
    account = LetsEncryptAccount.find_or_create
    return false if account.nil?
    chosen_cert = nil
    chosen_cert = user.lets_encrypts.selectable.first
    chosen_cert = user.lets_encrypts.create!(account: account) if chosen_cert.nil?
    if chosen_cert.nil?
      SystemEvent.create!(
        message: "Unable to generate LetsEncrypt for domain #{domain}",
        data: {
            domain: {
              id: id,
              name: domain
            },
            user: {
              id: user.id,
              email: user.email
            }
        },
        event_code: "26ed782e7ccfd47b"
      )
      return false
    end
    update_attribute :lets_encrypt, chosen_cert
  end

  def validate_le_domain
    if saved_change_to_attribute?("domain") && !skip_validation
      LetsEncryptWorkers::ValidateDomainWorker.perform_async(id)
    end
  end

  def disable_le_ready
    self.le_ready = false
  end

  # If the domain is no longer valid, OR if we disabled lets_encrypt, remove the association!
  def clean_lets_encrypt
    update_attribute(:lets_encrypt, nil) if lets_encrypt
  end

end
