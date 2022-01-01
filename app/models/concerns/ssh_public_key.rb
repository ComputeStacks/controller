module SshPublicKey
  extend ActiveSupport::Concern

  included do

    validates :pubkey, presence: true
    validate :validate_cert

    before_save :store_label
  end

  def public_key
    SSHData::PublicKey.parse_openssh pubkey
  end

  def fingerprint
    public_key.fingerprint
  end

  private

  def validate_cert
    public_key
  rescue
    errors.add(:pubkey, "is not a valid openssh public key")
  end

  def store_label
    return if pubkey.blank?
    self.label = pubkey.split(" ")[2].nil? ? nil : pubkey.split(" ")[2]
  end

end
