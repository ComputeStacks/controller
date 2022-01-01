module Users
  module OtpStorable
    extend ActiveSupport::Concern

    included do
      attr_accessor :otp_setup_code
    end

    def otp_secret
      return nil if otp_secret_enc.blank?
      Secret.decrypt! otp_secret_enc
    end

    def otp_secret=(value)
      return if value.blank?
      self.otp_secret_enc = Secret.encrypt! value
    end

    def totp_enabled?
      !otp_secret_enc.blank?
    end

  end
end
