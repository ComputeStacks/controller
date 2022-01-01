module ApiAuth
  extend ActiveSupport::Concern

  included do
    before_action :auth_request!, except: %i[ auth secondfactor ]
  end

  ##
  # =Deprecated token authentication
  def auth
    respond_to do |format|
      format.json { render json: { errors: ["this authentication method has been replaced with oauth2.", "Please see the api documentation: /documentation/api"] }, status: :bad_request }
      format.xml { render xml: { errors: ["this authentication method has been replaced with oauth2.", "Please see the api documentation: /documentation/api"] }, status: :bad_request }
    end
  end

  ##
  # =Request if user has 2FA enabled
  #
  # This is primarily used by SSO implementations, and billing integrations.
  #
  # 200 == no 2fa, or does not exist
  #
  # 401 == has 2fa.
  #
  # Route: +/api/user/:external_id/authcheck+
  #
  def secondfactor
    user = User.find_by(external_id: params[:external_id])
    status = :ok
    msg = {}
    if user.nil?
      msg = {errors: ['User does not exist.']}
      status = :not_found
    else
      if user.require_2fa_auth?
        if user.last_second_factor_auth && user.last_second_factor_auth > 8.hours.ago
          raw_ip = request.remote_ip
          # raw_ip = request.env['HTTP_X_FORWARDED_FOR'].nil? ? request.remote_ip : request.env['HTTP_X_FORWARDED_FOR']
          remote_ip = raw_ip.to_s.split(":ffff:").last
          specified_remote_ip = params[:rip]
          existing_ips = []
          existing_ips << user.last_sign_in_ip.to_s
          existing_ips << user.current_sign_in_ip.to_s
          if existing_ips.include?(remote_ip) || existing_ips.include?(specified_remote_ip)
            # We've seen this ip before
            status = :accepted
          else
            msg = {errors: ['Requires 2FA.']}
          end
        else
          msg = {errors: ['Requires 2FA.']}
        end
      else
        status = :accepted
      end
    end
    respond_to do |format|
      format.json { render json: msg, status: status }
      format.xml { render xml: msg, status: status  }
    end
  end

  protected

  ##
  # =Basic Auth Request
  def auth_request! # :doc:

    # Intercept OPTIONS request (used by CORS prior; auth will be missing.)
    # CORS headers are configured in nginx and will be appended to this response.
    return unknown_route if request.request_method == 'OPTIONS'

    # Allow basic auth -- all other auth types will be handled by OAuth.
    if request.authorization =~ /Basic/
      authenticate_with_http_basic do |username, password|
        auth = User::ApiCredential.find_by_username username
        resource = auth&.user
        if resource && auth.valid_password?(password)
          ##
          # No longer do this -- was causing session expired errors
          # sign_in(:user, resource)
          @current_user = resource
        end
      end
      return invalid_authentication unless @current_user
    end
  rescue
    return invalid_authentication
  end

  def current_user
    return @current_user if defined?(@current_user)
    if doorkeeper_token
      @current_user = User.find_by(id: doorkeeper_token[:resource_owner_id])
    end
  end

  ##
  # =Respond with Invalid Auth
  def invalid_authentication
    respond_to do |format|
      format.json { render json: {errors: ["Not Authorized"]}, status: :unauthorized }
      format.xml { render xml: {errors: ["Not Authorized"]}, status: :unauthorized  }
    end
  end

  private

  def auth_params
    params.permit(:api_key, :api_secret)
  end

end
