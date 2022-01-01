class Users::TotpController < AuthController

  def index; end

  def new
    @otp_secret = ROTP::Base32.random
    otp_setup = ROTP::TOTP.new @otp_secret, issuer: Setting.app_name
    @qr_code = qr_code otp_setup.provisioning_uri(current_user.email)
  end

  def create
    if totp_params[:otp_secret].blank? || totp_params[:otp_setup_code].blank? || totp_params[:current_password].blank?
      redirect_to '/users/totp/new', alert: "Missing OTP Parameters"
      return false
    end
    @otp_secret = totp_params[:otp_secret]
    otp_setup = ROTP::TOTP.new @otp_secret, issuer: Setting.app_name
    otp_timestamp = otp_setup.verify totp_params[:otp_setup_code], drift_behind: 15
    current_user.current_password = totp_params[:current_password]
    if otp_timestamp && current_user.valid?
      current_user.update otp_secret: @otp_secret, last_otp_at: otp_timestamp
      redirect_to "/users/security", success: "Two-Factor Authentication Enabled"
    else
      @qr_code = qr_code otp_setup.provisioning_uri(current_user.email)
      current_user.errors.add(:base, "Invalid authenticator code")  unless otp_timestamp
      render :new
    end
  end

  def destroy
    if current_user.update(otp_secret_enc: nil)
      flash[:success] = "Two Factor Auth Disabled"
    else
      flash[:alert] = "Failed to disable: #{current_user.errors.full_messages.join(' ')}"
    end
    redirect_to "/users/security"
  end

  private

  def qr_code(url)
    RQRCode::QRCode.new(url).as_png(resize_exactly_to: 300).to_data_url
  end

  def totp_params
    params.require(:user).permit(:otp_secret, :otp_setup_code, :current_password)
  end

end
