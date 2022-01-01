class LetsEncryptAccount < ApplicationRecord

  include PrivateKeyManager

  has_many :certificates, class_name: 'LetsEncrypt', foreign_key: 'account_id'

  before_validation :set_default_email, on: :create

  validates :email, presence: true

  def setup!
    return true unless self.account_id.blank?
    account = client.new_account(contact: "mailto:#{self.email}", terms_of_service_agreed: true)
    if account.kid.blank?
      false
    else
      self.update_attribute :account_id, account.kid
    end
  end

  def client
    if Rails.env.production?
      Acme::Client.new(
          private_key: private_key,
          directory: LE_DIRECTORY,
          kid: self.account_id.blank? ? nil : self.account_id,
          bad_nonce_retry: 5
      )
    else
      Acme::Client.new(
          private_key: private_key,
          directory: LE_DIRECTORY,
          kid: self.account_id.blank? ? nil : self.account_id,
          connection_options: { ssl: { verify: false } },
          bad_nonce_retry: 5
      )
    end
  end

  # @see [LetsEncrypt Integration Guide: One Account or Many?](https://letsencrypt.org/docs/integration-guide/#one-account-or-many)
  def self.find_or_create
    return LetsEncryptAccount.first if LetsEncryptAccount.exists?
    a = LetsEncryptAccount.create!
    a.setup!
    a
  end

  private

  def set_default_email
    self.email = 'admin@computestacks.com' if self.email.nil?
  end

end
