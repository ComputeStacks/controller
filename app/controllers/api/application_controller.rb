class Api::ApplicationController < ActionController::Base
  protect_from_forgery unless: -> { request.format.json? || request.format.xml? }

  include ApiAuth
  include ApiMissingRoute
  include ApiResponse
  include ApiScopes # must come after ApiAuth -- see the concern's ordering note
  include ApiVersion
  include LogPayload
  include Rails::Pagination

  before_action :set_locale, if: :current_user

  # `public` is a default scope, so any token can read the version; `admin_read`
  # is accepted as well so an admin-only application need not also ask for it.
  api_scope version: [:public, :admin_read]

  # `auth` is a deprecated stub that always 400s, `secondfactor` is deliberately
  # unauthenticated (it is excluded from `auth_request!` and is used by SSO and
  # billing integrations), and `unknown_route` is the 404 catch-all.
  api_scope_none :auth, :secondfactor, :unknown_route

  respond_to :json, :xml

  ##
  # Show Version Information
  #
  # `GET /version`
  #
  # * `version`: string
  # * `api_latest_version`: string
  # * `api_available_versions`: Array<Integer>
  #
  def version
    v = {
      "version" => COMPUTESTACKS_VERSION,
      "api_latest_version" => COMPUTESTACKS_VERSION.split(".")[0..1].join("").to_i,
      "api_available_versions" => VersionCake.config.versioned_resources.last.deprecated_versions + VersionCake.config.versioned_resources.last.supported_versions
    }
    respond_to do |format|
      format.json { render json: v }
      format.xml { render xml: v }
    end
  end

  private

  def set_locale
    if current_user && !current_user.locale.blank?
      if I18n.available_locales.include?(current_user.locale)
        I18n.locale = current_user.locale
      end
    end
  end
end
