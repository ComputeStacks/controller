##
# LetsEncrypt Certificates
#
# @!attribute id
#   @return [Integer]
# @!attribute crt
#   @return [String] Full LetsEncrypt Certificate, including CA.
# @!attribute expires_at
#   @return [Date]
# @!attribute last_generated_at
#   @return [Date]
# @!attribute names
#   @return [Array] List of domains included with this certifiate. Does not include pending domains (LetsEncryptAuth)
# @!attribute pkey
#   @return [String] Private Key
# @!attribute common_name
#   @return [String]
#
class LetsEncrypt < ApplicationRecord

  include PrivateKeyManager

  # Certificates with 20 or less domains. Used to determine who can accept more domains.
  # @!scope class
  # @return [Array<LetsEncrypt>]
  scope :selectable, -> { where("array_length(names, 1) < 21") }

  # @return [Array<EventLog>]
  has_and_belongs_to_many :event_logs

  # @return [Array<EventLogDatum>]
  has_many :event_details, through: :event_logs

  # @return [LetsEncryptAccount]
  belongs_to :account, class_name: 'LetsEncryptAccount'

  # @return [Array<LetsEncryptAuth>]
  has_many :lets_encrypt_auths, dependent: :destroy

  # @return [Array<Deployment::ContainerDomain>]
  has_many :container_domains, class_name: 'Deployment::ContainerDomain', dependent: :restrict_with_exception

  # @return [Array<LoadBalancer>]
  has_many :load_balancers, dependent: :nullify

  # @return [User]
  belongs_to :user, optional: true

  def friendly_name
    return '...' if common_name.blank? && names.empty?
    names.count > 1 ? "#{common_name} (+#{names.count - 1} more)" : common_name
  end

  def status
    if active? && (names != expected_domains)
      'Update Pending'
    elsif active?
       'Active'
    else
      'Inactive'
    end
  end

  # @return [Boolean]
  def active?
    !crt.blank?
  end

  # Select a common name based on the expected domains
  # @return [String]
  def select_common_name
    if common_name.blank?
      expected_domains[0]
    else
      expected_domains.include?(common_name) ? common_name : expected_domains[0]
    end
  end

  # Certificate & Private Key
  # @return [String] certificate
  def certificate_bundle
    return nil if pkey_encrypted.blank? || crt.blank?
    "#{crt}\n#{private_key.to_pem}".gsub("\n\n", "\n")
  end

  # If certificate expires within the next 25 days.
  # @return [Boolean]
  def can_renew?
    return true if expires_at.nil?
    (expires_at < 30.days.from_now) || (expected_domains != names)
  end

  # List of all expected domains, including those that have not been generated yet.
  # @return [Array] sorted list of domains
  def expected_domains
    ar = container_domains.lets_encrypt_ready.pluck(:domain)
    load_balancers.each do |lb|
      lb.dns_domains.each do |d|
        ar << d unless ar.include?(d)
      end
    end
    ar.sort
  end

  ##
  # Can we actually provision this certificate?
  #
  # This is different from `can_renew?` in that we're checking for LetsEncrypt (ACME) error states
  #
  # TODO: This will run every 20 minutes...find a way to silence these events?
  #
  # @return [Boolean]
  def can_provision?(event)
    return false if event.nil? # should never happen!

    # Fatal LE errors. Support needs to delete this event before it will proceed!
    if event_details.where("event_log_data.event_code = ?", 'ef1da605ec1b3927').exists?
      event.event_details.create!(
        data: 'Fatal LetsEncrypt error, contact support to clear these events before proceeding.',
        event_code: '2daeff4223ee9083'
      )
      event.cancel! "Contact Support"
      return false
    end

    # too many order attempts with the same set of domains
    if event_details.where("event_log_data.event_code = ? and event_log_data.created_at > ?", 'bdd38ea038297c94', 1.day.ago).exists?
      failed_domains = []
      event_details.where("event_log_data.event_code = ? and event_log_data.created_at > ?", 'dc53ef4622c4ef86', 1.day.ago).each do |i|
        d = i.data.strip.split(',')
        d.each do |dd|
          failed_domains << dd
        end
      end
      unless (expected_domains & failed_domains).empty?
        # We only want 1 of these stored!
        if event_details.where("event_log_data.event_code = ? AND event_log_data.created_at > ?", 'e996b1b404cafee0', 1.day.ago).exists?
          event.destroy
          return false
        end
        event.event_details.create!(
          data: "Unable to generate certificate, too many certificate generation attempts already on those domain names. Will attempt in 24 hours.",
          event_code: 'e996b1b404cafee0'
        )
        event.cancel! "Too many identical certificates"
        return false
      end
    end

    # too many failed authorizations / general rate limit. halt all for 1 day
    if EventLogDatum.where("event_log_data.event_code = ? and event_log_data.created_at > ?", 'befbf62f360b8958', 1.day.ago).exists?
      # We only want 1 of these stored!
      if event_details.where("event_log_data.event_code = ? AND event_log_data.created_at > ?", 'befbf62f360b8958', 1.day.ago).exists?
        event.destroy
        return false
      end
      # full stop!
      event.event_details.create!(
        data: "Unable to generate certificate due to rate limit with LetsEncrypt. Will attempt in 24 hours.",
        event_code: 'befbf62f360b8958'
      )
      event.cancel! "Rate limited by LetsEncrypt"
      return false
    end
    true
  end

end
