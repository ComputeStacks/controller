# https://doorkeeper.gitbook.io/guides/ruby-on-rails/getting-started

# frozen_string_literal: true
#
# Original Source: https://github.com/doorkeeper-gem/doorkeeper/blob/45b6ce568523a5e2f2cdc9c3ed60254d7891f8dc/lib/generators/doorkeeper/templates/initializer.rb

Doorkeeper.configure do
  # Change the ORM that doorkeeper will use (needs plugins)
  orm :active_record

  # This block will be called to check whether the resource owner is authenticated or not.
  resource_owner_authenticator do
    current_user || warden.authenticate!(scope: :user)
  end

  resource_owner_from_credentials do |routes|
    auth = User::ApiCredential.find_by_username params[:username]
    resource = auth&.user
    if resource && auth.valid_password?(params[:password])
      sign_in(:user, resource)
      resource
    else
      nil
    end
  end

  # This allows users to see `/oauth/applications` and manage their applications.
  admin_authenticator do |routes|
    # current_user && current_user.is_admin
    current_user || warden.authenticate!(scope: :user)
  end

  # Issue access tokens with refresh token (disabled by default), you may also
  # pass a block which accepts `context` to customize when to give a refresh
  # token or not. Similar to `custom_access_token_expires_in`, `context` has
  # the properties:
  #
  # `client` - the OAuth client application (see Doorkeeper::OAuth::Client)
  # `grant_type` - the grant type of the request (see Doorkeeper::OAuth)
  # `scopes` - the requested scopes (see Doorkeeper::OAuth::Scopes)
  #
  use_refresh_token do |context|
    context.grant_type == 'authorization_code'
  end

  # Provide support for an owner to be assigned to each registered application (disabled by default)
  # Optional parameter confirmation: true (default false) if you want to enforce ownership of
  # a registered application
  # NOTE: you must also run the rails g doorkeeper:application_owner generator
  # to provide the necessary support
  #
  enable_application_owner confirmation: false

  # Define access token scopes for your provider
  # For more information go to
  # https://github.com/doorkeeper-gem/doorkeeper/wiki/Using-Scopes
  #
  default_scopes :public
  optional_scopes :admin_read,
                  :admin_write,
                  :dns_read,
                  :dns_write,
                  :images_read,
                  :images_write,
                  :order_read,
                  :order_write,
                  :profile_update,
                  :profile_read,
                  :project_read,
                  :project_write,
                  :register # Can only be added to an oauth application by an administrator.

  # Define scopes_by_grant_type to restrict only certain scopes for grant_type
  # By default, all the scopes will be available for all the grant types.
  #
  # Keys to this hash should be the name of grant_type and
  # values should be the array of scopes for that grant type.
  # Note: scopes should be from configured_scopes(i.e. default or optional)
  #
  # scopes_by_grant_type password: [:write], client_credentials: [:update]

  # Forbids creating/updating applications with arbitrary scopes that are
  # not in configuration, i.e. `default_scopes` or `optional_scopes`.
  # (disabled by default)
  #
  enforce_configured_scopes

  # Specify what grant flows are enabled in array of Strings. The valid
  # strings and the flows they enable are:
  #
  # "authorization_code" => Authorization Code Grant Flow
  # "implicit"           => Implicit Grant Flow
  # "password"           => Resource Owner Password Credentials Grant Flow
  # "client_credentials" => Client Credentials Grant Flow
  #
  # If not specified, Doorkeeper enables authorization_code and
  # client_credentials.
  #
  # implicit and password grant flows have risks that you should understand
  # before enabling:
  #   http://tools.ietf.org/html/rfc6819#section-4.4.2
  #   http://tools.ietf.org/html/rfc6819#section-4.4.3
  #
  grant_flows %w[authorization_code client_credentials password]

  # WWW-Authenticate Realm (default "Doorkeeper").
  #
  realm "ComputeStacks"
end
