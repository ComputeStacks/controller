# Be sure to restart your server when you modify this file.

# Configure sensitive parameters which will be filtered from the log file.
Rails.application.config.filter_parameters += [
  :api_password,
  :api_secret, # deprecated in favor of `api_password`
  :authenticity_token, # csrf token
  :ca,
  :crt,
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
  :certificate,
  :otp,
  :ssn
]
