require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
require 'resolv'
module CloudPortal
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0
    config.autoload_paths += %W(#{config.root}/app/jobs #{config.root}/app/validators #{config.root}/lib/includes)
    config.time_zone = "UTC"
    config.i18n.default_locale = :en
    config.encoding = "utf-8"
    config.active_support.escape_html_entities_in_json = true
    config.action_dispatch.ip_spoofing_check = false
    config.active_job.queue_adapter = :sidekiq
    config.assets.enabled = true
    config.assets.initialize_on_precompile = false
    config.active_record.yaml_column_permitted_classes = [ActiveSupport::TimeZone, ActiveSupport::TimeWithZone, Time, DateTime, BigDecimal, Symbol, IPAddr]
    config.middleware.use Rack::Attack
    config.assets.precompile += ['*.svg']

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    config.to_prepare do
      Devise::SessionsController.layout "devise"
      Doorkeeper::ApplicationsController.layout "application"
      Doorkeeper::AuthorizationsController.layout "devise"
      Doorkeeper::AuthorizedApplicationsController.layout "application"
    end

    Money.rounding_mode = BigDecimal::ROUND_HALF_UP

    config.exceptions_app = self.routes
  end
end
