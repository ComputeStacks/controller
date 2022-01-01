class Auth::OauthAuthorizedApplicationsController < Doorkeeper::AuthorizedApplicationsController

  include BelcoWidget
  include EnforceSecondFactor
  include LogPayload
  include SentrySetup

end
