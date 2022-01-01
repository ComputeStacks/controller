class SessionsController < Devise::SessionsController

  rescue_from ActionController::InvalidAuthenticityToken, with: :csrf_invalid

  # auth_options = {:scope=>:user, :recall=>"sessions#new"}
  # params = { 'user' => { 'email' => '', 'password' => '' } }
  def create
    user_check = User.find_by(email: params['user']['email'])
    # The only way to get into a service account is by impersonating
    if user_check&.is_service_account?
      sign_out_all_scopes
      redirect_to "/login", alert: "You can not login to a service account this way."
      return false
    end
    self.resource = nil
    self.resource = warden.authenticate!(auth_options) if user_check
    if self.resource
      if self.resource.require_2fa_auth?
        session[:req_second_factor] = true
        self.resource.update_attribute :req_second_factor, true
      else
        session.delete(:req_second_factor)
        self.resource.update_attribute :req_second_factor, false if self.resource.req_second_factor
      end
      self.resource.update_attribute :bypass_second_factor, false if self.resource.bypass_second_factor
      # set_flash_message :notice, :signed_in ## no longer want flash messages on login.
      sign_in(resource_name, resource)
      yield resource if block_given?
      flash.delete(:notice) if self.resource.req_second_factor
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      super # No user & remote SSO disabled.
    end
  end

  private

  def csrf_invalid
    sign_out_all_scopes
    redirect_to "/login", alert: "Expired login form token, please try again."
  end

end
