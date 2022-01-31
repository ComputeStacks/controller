ruby "~> 2.7"

source 'https://rubygems.org'

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem 'timeout', '~> 0.1'

gem 'rails', '= 6.1.4.4'
gem 'json', '= 2.6.1'
gem 'redis', '= 4.5.1'
gem 'hiredis', '= 0.6.3', platform: :ruby

gem 'rack-attack', '= 6.5.0'

gem 'tzinfo-data', '= 1.2021.5' # No source of timezone data could be found. (TZInfo::DataSourceNotFound)

gem 'rake', '= 13.0.6'
gem 'sprockets', '= 4.0.2'
gem 'sprockets-rails', '= 3.2.2'
gem 'webpacker', '= 5.4.3'
gem 'pg', '= 1.2.3', platform: :ruby
gem 'jquery-rails', '= 4.3.5'

gem 'httparty', '= 0.18.1' # @deprecated for httprb
gem 'http', '= 4.4.1' # v5+ has breaking changes

gem 'geoip', '= 1.6.4'

gem 'will_paginate', '= 3.3.0'
gem 'api-pagination', '= 4.8.2'

gem 'money-rails', '= 1.14.0'
gem 'whois', '= 5.0.2'
gem 'coffee-rails', '= 5.0.0' # >= 5.0.0 requires rails 5.2

gem 'sidekiq', '= 6.3.1'
gem 'sidekiq-unique-jobs', '= 7.1.12'

# Logging
gem 'lograge', '= 0.11.2'

# Authentication
gem 'devise', '= 4.8.0'
gem 'bcrypt', '= 3.1.16'

gem "doorkeeper", "= 5.4.0" # TODO: move to v5.5 separately and verify nothing broke.

gem 'authy', '= 2.7.5'
gem 'rotp', '= 6.2.0'
gem 'rqrcode', '= 2.1.0'
gem 'webauthn', '= 2.5.0'

gem 'clockwork', '= 3.0.0'
gem 'http_accept_language', '= 2.1.1'

gem 'nokogiri', '= 1.12.5'

gem 'country_select', '= 6.0.0'
gem 'responders', '= 3.0.1'

gem 'daemons', '= 1.4.1'

gem 'haml', '= 5.2.2'
gem 'slim', '= 4.1.0'
#gem 'valvat', '= 0.6.10'
gem 'uglifier', '= 4.2.0'

gem 'chartkick', '= 4.0.5'
gem 'groupdate', '= 5.2.2'

gem 'ssh_data', '~> 1.1.0' # Generate & Validate SSH Keys
gem 'net-ssh', '= 6.1.0'
gem 'ed25519', '= 1.2.4'
gem 'bcrypt_pbkdf', '= 1.1.0'  # Support ed25519 ssh keys for net-ssh.
gem 'highline', '= 2.0.3' # Hide PW entered into net-ssh from logs and output.

# Markdown Support
gem 'github-markup', '= 4.0.0'
gem 'redcarpet', '= 3.5.1', platform: :ruby
gem 'sentry-raven', '= 3.1.1'

gem 'sass-rails', '= 6.0.0'
gem 'bootstrap-sass', '= 3.4.1'

gem 'rabl', '= 0.14.5'
gem 'oj', '= 3.13.7', platform: :ruby
gem 'jwt', '= 2.2.3'

#gem 'rbnacl', '= 4.0.2' # Support ed25519 ssh keys for net-ssh. >= 5.0 does not work.

# LetsEncrypt
gem 'acme-client', '= 2.0.9'

gem 'versioncake', '= 4.0.2'

# Console
gem 'pry', '= 0.14.1'
gem 'pry-rails', '= 0.3.9'

gem 'diplomat', '= 2.5.1'

gem 'fugit', '= 1.5.2'
gem 'zaru', '= 0.3.0'

##
# Currently does not support rails 6.1
#     gem 'acts-as-taggable-on', '= 6.5.0'
# Temporarily until rails 6.1 is officially released.
#     https://github.com/mbleigh/acts-as-taggable-on
# gem 'acts-as-taggable-on', github: 'mbleigh/acts-as-taggable-on', ref: '06bf141'
gem 'acts-as-taggable-on', '= 8.1.0'

gem 'liquid', '= 5.1.0' # Used to generate variables in custom commands

##
# Used by CAA check to determine TLD for a domain.
gem 'domain_prefix', '= 0.4.20210906' # https://github.com/postageapp/domain_prefix

gem 'dnsruby', '= 1.61.7' # https://github.com/alexdalitz/dnsruby

gem 'prometheus-api-client', '= 0.6.2'

# https://sandfox.dev/ruby/vishnu.html
gem 'vishnu'

group :development do
  gem 'passenger', '~> 6.0' # Now managed by container
  gem 'yard', '= 0.9.26'
  gem 'listen', '= 3.4.1'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem "better_errors", '= 2.9.1'
  gem "binding_of_caller", "= 1.0.0"
  gem 'rack-cors', '= 1.1.1'
  gem 'i18n-tasks'
end

group :test do
  gem 'minitest-reporters', '= 1.4.3'
  gem 'capybara', '~> 3.35'
  gem 'selenium-webdriver'
  gem 'webmock'
end

source "https://rubygems.pkg.github.com/computestacks" do
  gem "autodns", "2.1.1"
  gem "docker_registry", "0.2.3"
  gem "docker_ssh", "0.7.1"
  gem "docker_volume_local", "0.2.5"
  gem "docker_volume_nfs", "0.2.7"
  gem "pdns", "1.1.1"
  gem "whmcs", "2.3.4"
end

gem 'docker-api', github: 'ComputeStacks/docker-api', ref: 'a36e692'

# gem 'bootsnap', '= 1.4.9', require: false

# Assets
# http://insecure.rails-assets.org
# https://rails-assets.org
source 'http://insecure.rails-assets.org' do
  gem 'rails-assets-js-cookie', '= 2.1.4'
  gem 'rails-assets-jsTimezoneDetect', '= 1.0.6'
end

