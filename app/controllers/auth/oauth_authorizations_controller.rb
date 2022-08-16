class Auth::OauthAuthorizationsController < Doorkeeper::AuthorizationsController

  include BelcoWidget
  include EnforceSecondFactor
  include LogPayload
  include SentrySetup

  before_action :validate_user_scope!
  before_action :second_factor!
  before_action :set_token_replace!

  private

  # Doorkeeper: app/controllers.doorkeeper/authorizations_controller#52
  def redirect_or_render(auth)
    if auth.redirectable?
      redirect_path = if cookies.encrypted[:uri_token_replace].blank?
                        auth.redirect_uri
                      else
                        auth.redirect_uri.gsub(":token", cookies.encrypted[:uri_token_replace])
                      end
      if Doorkeeper.configuration.api_only
        render(
          json: { status: :redirect, redirect_uri: redirect_path },
          status: auth.status
        )
      else
        redirect_to redirect_path, allow_other_host: true
      end
    else
      render json: auth.body, status: auth.status
    end
  ensure
    session.delete(:uri_token_replace)
  end

  def set_token_replace!
    cookies.encrypted[:uri_token_replace] = {
      value: params[:token_replace],
      expires: 5.minutes.from_now
    } unless params[:token_replace].blank?
  end

  def validate_user_scope!
    if pre_auth.authorizable?
      if pre_auth.scopes.all.include?('admin') && !current_resource_owner.is_admin
        @msg = "You do not have access to the admin scope"
        return respond_to do |format|
          format.html { render template: 'doorkeeper/authorizations/general_error', layout: 'devise', status: :bad_request }
          format.json { render json: { errors: [@msg], status: :bad_request } }
          format.xml { render xml: { errors: [@msg], status: :bad_request } }
        end
      end
    end
  end

end
