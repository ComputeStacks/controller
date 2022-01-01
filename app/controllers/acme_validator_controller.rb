##
# Acme Validator Controller
#
# Handles ACME (LetsEncrypt) validation for services.
#
# The LoadBalancer will proxy HTTP verification requests back to the controlller,
# which will then respond with the correct code.
#
class AcmeValidatorController < ActionController::Base

  before_action :load_auth

  def show
    response.headers['Content-Type'] = 'text/plain'
    render plain: @auth_request.content, layout: false
  end

  private

  def load_auth
    # domain validation will use this placeholder to determine if the domain has any redirects
    # that would prevent the domain from being validated.
    if params[:id] == 'http_check'
      render plain: '', status: :ok, layout: false
      return false
    end
    @auth_request = LetsEncryptAuth.find_by(token: params[:id])
    if @auth_request.nil?
      render plain: '', status: :not_found, layout: false
      return false
    end
  end

end
