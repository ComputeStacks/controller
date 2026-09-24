# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :api_password,
  :api_secret, # deprecated in favor of `api_password`
  :authenticity_token, # csrf token
  :pkey,
  :cvv,
  :password,
  :password_confirmation,
  :state, # OAuth2 state parameter
  :secret,
  :token,
  :_key,
  :crypt,
  :salt,
  :otp,
  :ssn,
  # Service settings and env params keep their payload in a column literally named
  # `value` (also `static_value` / `env_value`), and those payloads are routinely
  # credentials -- database passwords, API keys. `send_default_pii` is on, so an
  # unfiltered `value` reaches both production.log and Sentry. Matching is substring
  # based, so this covers all three parameter names.
  :value
]
