class RegistrationController < ApplicationController

  rescue_from ActionController::InvalidAuthenticityToken, with: :csrf_invalid

  layout "devise"

  before_action :check_if_enabled

  # @deprecated Params are going away...this is from VM orders.
  def new
    if params[:m] && (params[:m].to_i > 256 && params[:m].to_i < 50000) && (params[:m].to_i % 512 == 0)
      if params[:c] && (params[:c].to_i > 0 && params[:c].to_i < 24)
        if params[:d] && (params[:d].to_i > 4 && params[:d].to_i < 2048) && (params[:d].to_i % 5 == 0)
          init_order = {
            'm' => params[:m].to_i,
            'c' => params[:c].to_i,
            'd' => params[:d].to_i,
            'p' => 0
          }
          session[:initial_order] = init_order
        end
      end
    end
    if params[:p] && params[:p].to_i > 0
      init_order = session[:initial_order].nil? ? {} : session[:initial_order]
      init_order['p'] = params[:p]
      begin
        @package = Product.find_by(id: params[:p])
      rescue
        @package = nil
      end
    end
    if params[:promo]
      locked_domain = request.base_url.gsub("https://",'').gsub("http://",'')
      cookies.encrypted[:promo] = {
        value: params[:promo],
        expires: 1.year.from_now,
        domain: locked_domain
      }
    end
    @user = User.new(currency: ENV['CURRENCY'])
  end

  def create
    unless /^[^@]+@[^@]+\.[^@]+$/.match? user_params[:email]
      redirect_to "/register", alert: I18n.t('devise.failure.invalid_email')
      return false
    end
    @user = User.new(user_params)
    if user_params[:currency].blank? || (BillingPlan.default&.available_currencies).include?(user_params[:currency])
      @user.currency = ENV['CURRENCY']
    else
      @user.currency = user_params[:currency].upcase
    end
    @user.current_sign_in_ip = request.remote_ip
    @user.skip_confirmation! unless Setting.smtp_configured?
    @user.tmp_updated_password = user_params[:password]
    if @user.save
      Audit.create_from_object!(@user, 'created', request.remote_ip, current_user)
      bypass_sign_in @user
      redirect_to "/deployments/orders", notice: I18n.t('devise.registrations.signed_up')
    else
      render template: 'registration/new'
    end
  end

  private

  def user_params
    params.require(:user).permit(:fname, :lname, :email, :password, :password_confirmation, :country, :address1, :address2, :city, :state, :zip, :vat, :company_name, :currency, :phone)
  end

  def check_if_enabled
    unless Setting.enable_signup_form?
      redirect_to "/"
      return false
    end
  end

  def csrf_invalid
    sign_out_all_scopes
    redirect_to "/register", alert: "Expired form token, please try again."
  end

end
