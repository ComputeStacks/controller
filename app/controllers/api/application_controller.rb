class Api::ApplicationController < ActionController::Base

  protect_from_forgery unless: -> { request.format.json? || request.format.xml? }

  include ApiAuth
  include ApiMissingRoute
  include ApiResponse
  include ApiVersion
  include LogPayload
  include Rails::Pagination

  before_action :set_locale, if: :current_user


  before_action only: :version, unless: :current_user do
    doorkeeper_authorize! :public, :admin_read # allow admins to read version without asking for the public scope.
  end

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
        "api_latest_version" => COMPUTESTACKS_VERSION.split(".")[0..1].join('').to_i,
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
