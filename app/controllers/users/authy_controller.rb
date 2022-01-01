class Users::AuthyController < AuthController

  before_action :setup_authy, except: :destroy

  def index
    redirect_to action: :new
  end

  def new
    if current_user.authy_id && current_user.authy_enabled
      redirect_to "/users/security", alert: "Authy already setup."
      return false
    end
  end

  # Verify installation
  def edit
    if current_user.authy_id.nil?
      redirect_to action: :new
      return false
    end
    if current_user.authy_enabled
      redirect_to "/users/security", alert: "Authy already setup."
      return false
    end
  end

  def create
    if params[:cellphone].to_s.blank? || params[:country_code].to_s.blank?
      redirect_to action: :new, alert: "Missing required parameters."
      return false
    end
    authy = Authy::API.register_user(
      email: current_user.email,
      cellphone: params[:cellphone],
      country_code: params[:country_code]
    )
    if authy.ok?
      current_user.update_attribute :authy_id, authy.id
      redirect_to "/users/authy/verify"
    else
      redirect_to action: :new, alert: "Error! #{authy.errors.inspect}"
    end
  end

  # Verify Instalation
  def update
    if params[:token].to_s.blank?
      redirect_to action: :edit, alert: "Missing Token."
      return false
    end
    response = Authy::API.verify(id: current_user.authy_id, token: params[:token])
    if response.ok?
      current_user.update_attribute :authy_enabled, true
      redirect_to "/users/security", notice: "Authy enabled."
    else
      redirect_to "/users/authy/verify", alert: "Invalid Token."
    end
  end

  def destroy
    current_user.update_attribute :authy_enabled, false
    redirect_to "/users/security", notice: "Authy disabled."
  end

  private

  def setup_authy
    if !Setting.authy || Setting.authy_api.to_s.blank?
      redirect_to "/users/security", alert: "Authy not setup."
      return false
    end
    if current_user.is_support_admin?
      redirect_to '/users/security', alert: 'Authy not available.'
      return false
    end
    Authy.api_key = Setting.authy_api
    Authy.api_uri = "https://api.authy.com/"
  end

  def authy_params
    params.permit(:country_code, :cellphone, :token)
  end

end
