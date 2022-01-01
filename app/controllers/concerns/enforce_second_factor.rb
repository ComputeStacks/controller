module EnforceSecondFactor

  extend ActiveSupport::Concern

  private

  def second_factor!
    if current_user
      if current_user.req_second_factor || session[:req_second_factor]
        current_user.update_column(:req_second_factor, true) unless current_user.req_second_factor
        redirect_to "/users/security_key_auth/new"
        return false
      end
    end
  end

end
