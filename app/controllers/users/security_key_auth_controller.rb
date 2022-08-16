class Users::SecurityKeyAuthController < ApplicationController

  layout "devise"

  before_action :authenticate_user!

  def index
    redirect_to action: :new
  end

  def new
    current_user.lock_access! if current_user.failed_attempts >= Devise.maximum_attempts
    if current_user.access_locked?
      session.delete(:req_second_factor)
      sign_out current_user
      # "Your account has been locked for too many failed attempts. Please contact support."
      redirect_to "/login", alert: I18n.t('devise.failure.locked')
      return false
    end
    # Skip for users already authenticated
    unless current_user.req_second_factor
      redirect_to "/deployments"
      return false
    end

    # Sanity check: Ensure we actually have 2FA and therefore, should be here.
    # Support Admin will be prevented from logging in here.
    if current_user.is_support_admin? && !current_user.has_2fa?
      session.delete(:req_second_factor)
      sign_out current_user
      redirect_to "/login", alert: "Two-Factor Authentication is disabled, unable to login."
      return false
    elsif !current_user.has_2fa?
      current_user.update_column :req_second_factor, false
      session.delete(:req_second_factor)
      redirect_to '/deployments'
      return false
    end

    @selected_auth = nil
    case params[:t]
    when 'webauthn'
      @selected_auth = 'webauthn'
    when 'totp'
      @selected_auth = 'totp'
    end
    if @selected_auth.nil? # last = highest priority
      @selected_auth = 'totp' if current_user.totp_enabled?
      @selected_auth = 'webauthn' if current_user.security_keys.exists?
    end
    if @selected_auth.nil?
      session.delete(:req_second_factor)
      sign_out current_user
      redirect_to "/login", alert: "Error loading two factor auth. Please contact support."
      return false
    end
    @available_auths = []
    @available_auths << '<a href="?t=webauthn">Security Key</a>' if current_user.security_keys.exists? && @selected_auth != 'webauthn'
    @available_auths << '<a href="?t=totp">Authenticator App</a>' if current_user.totp_enabled? && @selected_auth != 'totp'
    if @selected_auth == 'webauthn'
      auth_challenge = WebAuthn::Credential.options_for_get(
        allow: current_user.security_keys.map { |i| Base64.strict_decode64(i.webauthn_id) }
      )
      cookies.encrypted[:authentication_challenge] = {
        value: auth_challenge.challenge,
        expires: 2.minutes.from_now
      }
      @request_data = auth_challenge.to_json
    else
      # When switching to other method, delete existing challenge.
      # By default, if they have a key, they will be presented with that first.
      cookies.delete(:authentication_challenge)
    end
  end

  def create
    if params[:type] == 'webauthn'
      begin
        webauthn_credential = WebAuthn::Credential.from_get Oj.load(params[:publicKeyCredential])
        stored_credential = current_user.security_keys.find_by(webauthn_id: Base64.strict_encode64(webauthn_credential.id))

        if stored_credential.nil?
          sign_out current_user
          redirect_to "/login", alert: "Error! Unknown Security Key"
          return false
        end

        webauthn_credential.verify(
          cookies.encrypted[:authentication_challenge],
          public_key: stored_credential.public_key,
          sign_count: stored_credential.counter
        )
        stored_credential.update_column :counter, webauthn_credential.sign_count

      rescue WebAuthn::SignCountVerificationError
        # Cryptographic verification of the authenticator data succeeded, but the signature counter was less then or equal
        # to the stored value. This can have several reasons and depending on your risk tolerance you can choose to fail or
        # pass authentication. For more information see https://www.w3.org/TR/webauthn/#sign-counter
        sign_out current_user
        redirect_to "/login", alert: "Error! Login counter provided is less than our records. Your device may have been cloned, please contact support."
        return false
      #rescue WebAuthn::Error => e
      rescue => e # We could also get `EncodingError`
        sign_out current_user
        redirect_to "/login", alert: "Error! #{e.message}"
        return false
      end
    elsif params[:type] == 'totp'
      otp_setup = ROTP::TOTP.new current_user.otp_secret, issuer: Setting.app_name
      otp_timestamp = otp_setup.verify params[:response], drift_behind: 15
      if otp_timestamp
        current_user.update last_otp_at: otp_timestamp
      else
        current_user.increment :failed_attempts
        redirect_to "/users/security_key_auth/new?t=totp", alert: 'Invalid Code'
        return false
      end
    else
      redirect_to action: :new, alert: I18n.t('users.security_key_auth.controller.invalid_token')
      return false
    end
    current_user.update(
      req_second_factor: false,
      failed_attempts: 0,
      last_second_factor_auth: Time.now
    )
    session.delete(:req_second_factor)
    redirect_to after_sign_in_path_for(current_user), notice: I18n.t('devise.sessions.signed_in')
  ensure
    cookies.delete(:authentication_challenge)
  end

  # Cancel auth request.
  def destroy
    sign_out current_user
    session.delete(:req_second_factor)
    cookies.delete(:authentication_challenge)
    redirect_to "/login"
  end

  private

  def security_params
    params.permit(:response, :type)
  end

end
