class Secret < ApplicationRecord

  attr_accessor :data

  before_save :encrypt_data

  validates :key_name, presence: true

  # Return related object
  def rel
    eval("#{rel_model}").where(id: rel_id).first
  end

  def decrypted
    Secret.decrypt!(encrypted_data)
  rescue
    nil
  end

  ## CLASS METHODS #####
  class << self

    # Generic Encrypt / Decrypt
    def encrypt!(params)
      crypt_key.encrypt_and_sign(params)
    end

    def decrypt!(params)
      begin
        crypt_key.decrypt_and_verify(params)
      rescue
        nil
      end
    end

    protected

    ##
    # Provide ActiveSupport::MessageEncryptor with local secret key.
    #
    # aes-256-cbc only takes the first 32 characters. Ruby <2.4 would truncate the keys automatically, now 2.4 requires a strict key length of 32.
    #
    # ActiveSupport::MessageVerifier will take the full 128 key, so we need to pass both.
    #
    # TODO: Upgrade from `cbc` to `gcm` encryption. https://github.com/rails/rails/pull/29263/files
    #
    def crypt_key
      ActiveSupport::MessageEncryptor.new(
        Rails.application.secrets.secret_key_base.byteslice(0,32),
        Rails.application.secrets.secret_key_base,
        cipher: "aes-256-cbc",
        digest: 'SHA256'
      )
    end
  end
  ## END SELF #####

  private

  def encrypt_data
    self.encrypted_data = Secret.encrypt!(self.data) unless self.data.blank?
  end

end
