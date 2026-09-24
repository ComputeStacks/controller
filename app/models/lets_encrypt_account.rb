class LetsEncryptAccount < ApplicationRecord
  include PrivateKeyManager

  has_many :certificates, class_name: "LetsEncrypt", foreign_key: "account_id"

  before_validation :set_defaults, on: :create

  validates :email, presence: true

  def setup!
    return true unless account_id.blank?
    account = if LetsEncryptAccount.acme_uses_eab?
      client.new_account(
        contact: "mailto:#{email}",
        terms_of_service_agreed: true,
        external_account_binding: {
          kid: Setting.acme_kid,
          hmac_key: Setting.acme_hmac_key
        }
      )
    else
      client.new_account(contact: "mailto:#{email}", terms_of_service_agreed: true)
    end
    if account.kid.blank?
      false
    else
      update_attribute :account_id, account.kid
    end
  end

  def client
    Acme::Client.new(
      private_key: private_key,
      directory: acme_directory,
      kid: account_id.presence,
      connection_options: {ssl: {verify: Rails.env.production?}},
      bad_nonce_retry: 10
    )
  end

  def self.find_or_create
    # https://letsencrypt.org/docs/integration-guide/#one-account-or-many
    # a = nil
    # can_include = 300
    # LetsEncryptAccount.all.each do |i|
    #   if i.certificates.count < can_include
    #     a = i
    #     break
    #   end
    # end

    # Find based on the _current_ default directory
    a = LetsEncryptAccount.where(acme_directory: LetsEncryptAccount.acme_directory).where.not(account_id: nil).first
    return a unless a.nil?

    a = LetsEncryptAccount.create!
    a.setup!
    a
  end

  # Allow us to override directory for test env
  def self.acme_directory
    return Setting.acme_directory unless Rails.env.test?

    "https://#{ENV["DOCKER_IP"]}:#{ENV["ACME_API_PORT"]}/dir"
  end

  # Is our default provider setup to use external account binding?
  def self.acme_uses_eab?
    !(Setting.acme_kid.blank? || Setting.acme_hmac_key.blank?)
  end

  private

  def set_defaults
    self.email = Setting.acme_email
    self.acme_directory = LetsEncryptAccount.acme_directory
  end
end
