class Users::SecurityKeyController < AuthController

  def index; end

  def new
    create_challenge = WebAuthn::Credential.options_for_create(
      user: { id: current_user.webauthn_id, name: current_user.email },
      exclude: current_user.security_keys.map { |i| Base64.strict_decode64(i.webauthn_id) }
    )
    cookies.encrypted[:creation_challenge] = {
      value: create_challenge.challenge,
      expires: 2.minutes.from_now
    }
    @request_data = create_challenge.to_json
    @key = current_user.security_keys.new
    render layout: 'devise'
  end

  def create
    if params[:publicKeyCredential].blank?
      redirect_to "/users/security_key/new", alert: "Missing Security Key Data"
      return false
    end
    webauthn_credential = WebAuthn::Credential.from_create Oj.load(params[:publicKeyCredential])
    webauthn_credential.verify cookies.encrypted[:creation_challenge]
    current_user.security_keys.create!(
      label: security_params[:label],
      webauthn_id: Base64.strict_encode64(webauthn_credential.id),
      public_key: webauthn_credential.public_key,
      counter: webauthn_credential.sign_count
    )
    redirect_to "/users/security_key", notice: I18n.t('users.security_key.controller.u2f.added')
  rescue => e
    redirect_to "/users/security_key/new", alert: "Error! #{e.message}"
  ensure
    cookies.delete(:creation_challenge)
  end

  def destroy
    @seckey = current_user.security_keys.find_by(id: params[:id])
    if @seckey.nil?
      redirect_to "/users/security_key", alert: "Key not found."
      return false
    end
    if @seckey.destroy
      audit = Audit.create_from_object!(current_user, 'updated', request.remote_ip, current_user)
      audit.update_attribute :raw_data, "Removed key: #{@seckey.label}"
      flash[:notice] = I18n.t('users.security_key.controller.removed')
    else
      # "Error removing Security Key: #{}"
      flash[:alert] = I18n.t('users.security_key.controller.errors.removed', { error: @seckey.errors.full_messages.join(' ') })
    end
    redirect_to action: :index
  end

  private

  def security_params
    params.require(:user_security_key).permit(:label)
  end

end
