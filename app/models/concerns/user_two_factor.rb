module UserTwoFactor

  extend ActiveSupport::Concern

  def has_2fa?
    !self.security_keys.empty? || totp_enabled?
  end

  def require_2fa_auth?
    return false if self.bypass_second_factor
    return true if is_support_admin? # && Rails.env.production?
    has_2fa?
  end


  # Re-enable 2FA
  def enable_2fa!
    update_attribute :bypass_second_factor, false
  end

  # Temporarily disable 2Fa
  def disable_2fa!
    update(
        bypass_second_factor: true,
        req_second_factor: false
    )
  end

end
