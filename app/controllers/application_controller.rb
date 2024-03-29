class ApplicationController < ActionController::Base

  include ApplicationErrors
  include BelcoWidget
  include EnforceSecondFactor
  include LogPayload
  include SentrySetup

  protect_from_forgery with: :exception, prepend: true

  before_action :catch_sso!

  rescue_from ActionController::BadRequest, with: :bad_request
  rescue_from ActionController::UnknownFormat, with: :unknown_route
  rescue_from ActionController::RoutingError, with: :unknown_route
  rescue_from ActionController::InvalidAuthenticityToken, with: :token_error

  before_action :check_suspended, if: :current_user


  around_action :set_time_zone

  before_action :check_route, unless: :current_user
  after_action :audit_log, if: :current_user
  before_action :set_locale

  before_action :auth_from_token! # Display a message when being redirected by SSO due to missing 2FA.

  add_flash_types :success


  def after_sign_in_path_for(resource)
    if session["user_return_to"].blank? || %w(/ /login /users/login).include?(session["user_return_to"])
      "/deployments"
    else
      session["user_return_to"]
    end
  end

  def after_sign_out_path_for(resource)
    "/login"
  end

  def portal_not_setup!
    render layout: "devise", template: "layouts/not_setup"
  end

  def set_time_zone(&block)
    if cookies['browser.timezone'] && cookies['browser.timezone'] != 'undefined'
      Time.use_zone(cookies['browser.timezone'], &block)
      if current_user
        current_user.update_attribute :timezone, cookies['browser.timezone'] unless current_user.timezone == cookies['browser.timezone']
      end
    else
      Time.use_zone('UTC', &block)
    end
  rescue
    Time.use_zone('UTC', &block)
  end

  private

  def catch_sso!
    flash[:alert] = I18n.t('devise.failure.sso_secondfactor') if params[:from_sso]
  end

  ##
  # Authenticate via short-lived token generated by SSO Admin API Call
  # GET /?username=EMAIL&token=AUTH_TOKEN
  #
  # Add `&from_admin=true` to add some specifics for administrators.
  #
  def auth_from_token!
    user = (params[:username] && params[:token]) && User.find_by(email: params[:username])
    if user && (!user.auth_token.nil? && !user.auth_token_exp.nil?)
      if user.auth_token_exp > Time.now && ActiveSupport::SecurityUtils.secure_compare(params[:token], user.auth_token)
        sign_in(:user, user, bypass: true)
        # TODO: Add session noting that this is from an admin, and lets put a big red bar at the top.
        login_path = if params[:from_admin]
          '/deployments'
        else
          user.subscriptions.empty? ? "/deployments/orders" : "/deployments"
        end
        redirect_to login_path
        return false
      else
        redirect_to "/login", alert: t('devise.failure.invalid')
        return false
      end
    end
  rescue
    nil
  end

  def set_locale
    session[:lang] = params[:lang] if params[:lang]
    if session[:lang]
      if I18n.available_locales.include?(session[:lang].to_sym)
        I18n.locale = session[:lang]
      else
        I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
        session.delete(:lang)
      end
    else
      I18n.locale = http_accept_language.compatible_language_from(I18n.available_locales)
    end
    if current_user
      current_user.update_column(:locale, I18n.locale) unless current_user.locale == I18n.locale
    end
    # I18n.locale = current_user.try(:locale) || I18n.default_locale
  rescue
    # If it fails, it's an invalid param, so lets gracefully fail on this.
  end

  def check_suspended
    if !current_user.active && request.fullpath != "/logout"
      if request.xhr?
        render plain: '', layout: false
      else
        render template: "layouts/shared/suspended", layout: "layouts/devise"
      end
      return false
    end
  end

  def audit_log
    current_user.update_columns(
        last_request_at: Time.now,
        last_request_ip: request.remote_ip.gsub("::ffff:","")
    )
  end

  def check_route
    if !current_user && request.fullpath == "/" && request.get?
      redirect_to "/login"
      return false
    end
  end

end
