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

    config.traces_sample_rate = if ENV['SENTRY_TRACE_SAMPLE_RATE'].blank?
                                  0.2
                                elsif ENV['SENTRY_TRACE_SAMPLE_RATE'].to_f > 1.0
                                  1.0
                                elsif ENV['SENTRY_TRACE_SAMPLE_RATE'].to_f < 0.0
                                  0.0
                                else
                                  ENV['SENTRY_TRACE_SAMPLE_RATE'].to_f
                                end
  end
end
