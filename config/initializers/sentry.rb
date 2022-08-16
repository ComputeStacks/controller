##
# Sentry
#
SENTRY_CONFIGURED = !ENV['SENTRY_DSN'].blank?
if SENTRY_CONFIGURED
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.enabled_environments = %w[ default test development production ] # Default is used by clockwork
    config.release = "controller@#{File.read("#{Rails.root}/VERSION").strip}"

    config.traces_sample_rate = 0.5
  end
end
