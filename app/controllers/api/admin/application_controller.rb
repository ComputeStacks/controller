##
# =ComputeStacks Admin API
# Welcome to the ComputeStacks API for Administrators. Any ComputeStacks user with admin privileges can access this endpoint; they simply need to use their user's API credentials.
#
# For security & safety, we recommend users create a standalone API user account with admin rights for any integration they plan to use with ComputeStacks.
#
# ==Versions
#
# To set the API version, modify the +Accept+ header with: +application/json; api_version=50+, where <i>50</i> is the version of the API.
#
# ==Authentication
#
# ComputeStacks supports 2 types of authentication strategies:
#
# ====Token Authentication (Recommended)
#
# To generate a token, first call the Authenticate API method and submit your API credentials. If successful, a JSON token will be returned. This token will expire in <b>5 days</b>, or until new credentials are generated.
#
# Now that you have your token, you will want to pass that in the <i>Authorization</i> header for all future requests.
#
# ====Invalidating tokens / api keys
# When you generate a new api key in ComputeStacks, any previously generated tokens will be immediately invalidated.
#
#
# <b>Example Authentication Requests:</b>
#     curl -X POST -u {{api_key}}:{{api_secret}} https://{{endpoint}}/api/auth
#
#     /* OR */
#
#     curl -X POST -H "Content-Type: application/json" -d '{"api_key": "{{api_key}}", "api_secret":"{{api_secret}}"}' https://{{endpoint}}/api/auth
#
#
#
# <b>Example Response:</b>
#
#     {
#         "token": "{{auth_token}}"
#     }
#
#
# <b>Future API Calls:</b>
#
# Always include the +Authorization+ header with future requests:
#
#
#     curl -H "Authorization: Bearer <token>" https://{{endpoint}}/api/
#
#
#
# ====Basic Auth
#
# You can optionally use standard basic authentication for any of the API endpoints.
#
# <i><b>Note:</b> This strategy has a lower threshold for rate limiting, so for lower-latency and higher throughput, we highly recommend using the token authentication strategy and caching the token.</i>
#
#
# <b>Example</b>
#
#     curl -u {{api_key}}:{{api_secret}} https://{{endpoint}}/api/deployments
#
#
#
# ==Successful Responses
#
# The following HTTP codes may be returned to denote a successful response:
#
# - 200 OK
# - 201 Created
# - 202 Accepted
#
# ==Error Handling
#
# The following error codes may be returned. If any error messages exist, they will be passed to the +{errors: []}+ field.
#
# - 400 Bad Request
# - 401 Unauthorized
# - 404 Not Found
# - 408 Request Timeout
# - 422 Unprocessable Entity
# - 500 Internal Server Error
#
#
# ==Collection Pagination
#
# Collection size, and the current page, is set by the headers +Per-Page+ and +Total+. To set these values in your request, pass the URL params +page=+ and +per_page=+.
#
# ==Web Hooks
#
# Web Hooks can be configured in the Administrator, under +Advanced Settings+.
#
# They support either +JSON+ or +XML+ -- see the setting titled +webhook_format+ in the admin.
#
# Currently available webhooks are:
# [+webhook_billing_event+] This is called every time a billing event occures. Currently, this includes:
# * New Orders
# * Order Cancellations
# * Upgrade / Downgrade
# * Change in phase (e.g. moving from free trial to final phase)
#
# [+webhook_billing_usage+] This is called on the last day of every month at 23:00 server time and includes all overage and usage (metered) data for each user.
#
# [+webhook_users+] Called each time a user's name, email, address, or password is updated.
#
class Api::Admin::ApplicationController < Api::ApplicationController

  before_action :ensure_admin!

  before_action -> { doorkeeper_authorize! :admin_read }, only: %i[index show], unless: :current_user
  before_action -> { doorkeeper_authorize! :admin_write }, only: %i[update create destroy], unless: :current_user

  private

  ##
  # =Require admin rights for all endpoints.
  def ensure_admin! # :doc:
    return invalid_authentication unless current_user&.is_admin
  end

end
