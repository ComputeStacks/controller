ruby "~> 3.2"

source 'https://rubygems.org'

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem 'timeout', '= 0.3.0'

gem 'rails', '= 7.0.4'
gem 'json', '= 2.6.3'
gem 'redis', '= 4.8.0' # v5 requires sidekiq v7+
gem 'hiredis', '= 0.6.3', platform: :ruby

gem 'rack-attack', '= 6.6.1'

gem 'tzinfo-data', '= 1.2022.7' # No source of timezone data could be found. (TZInfo::DataSourceNotFound)

gem 'rake', '= 13.0.6'
gem 'sprockets', '= 4.2.0'
gem 'sprockets-rails', '= 3.4.2'
gem 'webpacker', '= 5.4.3'
gem 'pg', '= 1.4.5', platform: :ruby
gem 'jquery-rails', '= 4.5.1'

gem 'httparty', '= 0.21.0' # @deprecated for httprb
gem 'http', '= 5.1.1'

gem 'geoip', '= 1.6.4'

gem 'will_paginate', '= 3.3.1'
gem 'api-pagination', '= 5.0.0'

gem 'money-rails', '= 1.15.0'
gem 'whois', '= 5.1.0'
gem 'coffee-rails', '= 5.0.0'

gem 'sidekiq', '= 6.5.8'
gem 'sidekiq-unique-jobs', '= 7.1.29'

# Logging
gem 'lograge', '= 0.12.0'

# Authentication
gem 'devise', '= 4.8.1'
gem 'bcrypt', '= 3.1.18'

gem "doorkeeper", "= 5.6.2"

gem 'rotp', '= 6.2.2'
gem 'rqrcode', '= 2.1.2'
gem 'webauthn', '= 2.5.2'

gem 'clockwork', '= 3.0.1'
gem 'http_accept_language', '= 2.1.1'

gem 'nokogiri', '= 1.14.2'

gem 'country_select', '= 8.0.1'
gem 'responders', '= 3.0.1'

gem 'daemons', '= 1.4.1'
gem 'net-smtp'
gem 'slim', '= 4.1.0'
#gem 'valvat', '= 0.6.10'
gem 'uglifier', '= 4.2.0'

gem 'chartkick', '= 4.2.1'
gem 'groupdate', '= 6.1.0'

gem 'ssh_data', '= 1.3.0' # Generate & Validate SSH Keys
gem 'net-ssh', '= 7.0.1'
gem 'ed25519', '= 1.3.0'
gem 'bcrypt_pbkdf', '= 1.1.0'  # Support ed25519 ssh keys for net-ssh.
gem 'highline', '= 2.1.0' # Hide PW entered into net-ssh from logs and output.

# Markdown Support
gem 'github-markup', '= 4.0.1'
gem 'redcarpet', '= 3.5.1', platform: :ruby


gem "sentry-ruby"
gem "sentry-rails"
gem "sentry-sidekiq"

gem 'sass-rails', '= 6.0.0'
gem 'bootstrap-sass', '= 3.4.1'

gem 'rabl', '= 0.16.1'
gem 'oj', '= 3.13.23', platform: :ruby
gem 'jwt', '= 2.6.0'

# LetsEncrypt
gem 'acme-client', '= 2.0.11'

gem 'versioncake', '= 4.1.1'

# Console
gem 'pry', '= 0.14.2'
gem 'pry-rails', '= 0.3.9'

gem 'diplomat', '= 2.6.4'

gem 'fugit', '= 1.5.3'
gem 'zaru', '= 0.3.0'

gem 'acts-as-taggable-on', '= 9.0.1'

gem 'liquid', '= 5.4.0' # Used to generate variables in custom commands

##
# Used by CAA check to determine TLD for a domain.
gem 'domain_prefix', '= 0.4.20210906' # https://github.com/postageapp/domain_prefix

gem 'dnsruby', '= 1.61.9' # https://github.com/alexdalitz/dnsruby

gem 'prometheus-api-client', '= 0.6.2'

gem 'font-awesome-sass', '= 6.2.1'

group :development do
  gem 'passenger', '~> 6.0' # Now managed by container
  gem 'yard', '= 0.9.28'
  gem 'listen', '= 3.8.0'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem "better_errors", '= 2.9.1'
  gem "binding_of_caller", "= 1.0.0"
  gem 'rack-cors', '= 1.1.1'
  gem 'i18n-tasks'
  gem 'solargraph'
end

group :test do
  gem 'minitest-reporters', '= 1.5.0'
  gem 'capybara', '~> 3.38'
  gem 'selenium-webdriver'
  gem 'webmock'
end

source "https://rubygems.pkg.github.com/computestacks" do
  gem "autodns", "2.1.1"
  gem "docker_registry", "0.3.4"
  gem "docker_ssh", "0.7.1"
  gem "docker_volume_local", "0.2.5"
  gem "docker_volume_nfs", "0.2.7"
  gem "pdns", "1.1.1"
  gem "whmcs", "2.3.6"
end

gem 'docker-api', github: 'ComputeStacks/docker-api', ref: 'a36e692'

# Assets
# http://insecure.rails-assets.org
# https://rails-assets.org
source 'http://insecure.rails-assets.org' do
  gem 'rails-assets-js-cookie', '= 2.1.4'
  gem 'rails-assets-jsTimezoneDetect', '= 1.0.6'
end

