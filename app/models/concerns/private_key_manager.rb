module PrivateKeyManager
  extend ActiveSupport::Concern

  included do
    before_save :init_private_key, if: Proc.new { pkey_encrypted.blank? }
  end

  def private_key
    return nil if pkey_encrypted.blank?
    OpenSSL::PKey::EC.new Secret.decrypt!(pkey_encrypted)
  end

  private

  def init_private_key
    self.pkey_encrypted = Secret.encrypt! OpenSSL::PKey::EC.generate("prime256v1").to_pem
  end

end
