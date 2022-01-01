module ApiVersion
  extend ActiveSupport::Concern

  included do
    rescue_from VersionCake::UnsupportedVersionError, with: :render_unsupported_version
    rescue_from VersionCake::ObsoleteVersionError, with: :render_unsupported_version
    before_action :include_deprecation
    helper_method :current_api_version
  end

  private

  ##
  # =Unknown API Version Error
  #
  def render_unsupported_version
    Rails.logger.warn "UNSUPPORTED API VERSION: #{request.headers['HTTP_ACCEPT']}"
    headers['API-Version-Supported'] = 'false'
    # If they pass some weird header, gracefully fail.
    begin
      requested_version = request.headers['HTTP_ACCEPT'].split("; ").last.split("=").last
      msg = "You requested an unsupported version (#{requested_version})"
    rescue
      msg = "You requested an unsupported version"
    end
    respond_to do |format|
      format.json { render json: {errors: [msg]}, status: :unprocessable_entity }
      format.xml { render xml: {errors: [msg]}, status: :unprocessable_entity  }
    end
  end

  def include_deprecation
    headers['API-Deprecated'] = 'true' if is_deprecated_version?
  end

  def current_api_version
    request_version
  end

end
