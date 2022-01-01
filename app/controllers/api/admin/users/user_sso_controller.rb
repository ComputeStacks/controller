##
# # SSO Service
#
# The purpose of this endpoint is to allow you to seamless log a user into ComputeStacks.
# Use cases for this could include: website registration process, accessing from a billing platform, or integrating with an existing control panel.
#
# You could also use this endpoint to verify a user has valid credentials as a way to leverage ComputeStacks as your authentication backend, without actually logging them into ComputeStacks.
#
# This returns an `auth_token` that can be included in a redirect URL to auto-login a user.
#
#     https://my-cs-install.com/?username={{user_email}}&token={{auth_token}}
#
class Api::Admin::Users::UserSsoController < Api::Admin::Users::BaseController

  ##
  # Generate SSO Credential
  #
  # `POST /api/admin/users/{id}/user_sso`
  #
  # Returns:
  # * `username`: String
  # * `token`: String
  # * `expires`: DateTime
  #
  def create
    unless @user.update( auth_token: SecureRandom.urlsafe_base64(24), auth_token_exp: 1.minute.from_now )
      return api_obj_error(@user.errors.full_messages)
    end
    msg = {
      username: @user.email,
      token: @user.auth_token,
      expires: @user.auth_token_exp
    }
    respond_to do |format|
      format.json { render json: msg, status: :created }
      format.xml { render xml: msg, status: :created }
    end
  end

end
