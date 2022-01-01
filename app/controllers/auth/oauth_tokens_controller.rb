class Auth::OauthTokensController < Doorkeeper::TokensController

  include BelcoWidget
  include LogPayload
  include SentrySetup

  before_action :enforce_user_scopes!, only: :create

  private

  ##
  # Enforce scopes by user type.
  #
  # * [`admin_read`, `admin_write`] Must be an admin user
  # * [`*`] Must have a user account, otherwise forced to only supply `public` scope.
  #
  def enforce_user_scopes!
    if authorize_response.is_a?(Doorkeeper::OAuth::TokenResponse)
      user = User.find_by(id: authorize_response.token.resource_owner_id)
      scopes = authorize_response.token.scopes
      if user.nil?
        unless allow_nil_user?(scopes)
          render json: { error: :unauthorized_client, error_description: I18n.t(:invalid_scope, scope: %i[doorkeeper errors messages]) }, status: :forbidden
        end
      elsif scopes.include?("admin_read") || scopes.include?("admin_write")
        if !user.is_admin
          render json: { error: :unauthorized_client, error_description: I18n.t(:invalid_scope, scope: %i[doorkeeper errors messages]) }, status: :forbidden
        end
      end
    end
  rescue ActiveRecord::NotNullViolation, Doorkeeper::Errors::MissingRequiredParameter
    render json: { error: :unauthorized_client, error_description: I18n.t(:server_error, scope: %i[doorkeeper errors messages]) }, status: :forbidden
  rescue => e
    ExceptionAlertService.new(e, 'b18ecdcb8c9cf922').perform
    Rails.logger.warn(e.message) if Rails.env.development?
    render json: { error: :unauthorized_client, error_description: I18n.t(:server_error, scope: %i[doorkeeper errors messages]) }, status: :forbidden
  end

  ##
  # Can this application generate a token?
  #
  # Must only contain any or all of:
  # * public
  # * register
  #
  def allow_nil_user?(scopes)
    (scopes + %w(public register)).uniq.sort == %w(public register).sort
  end

end
