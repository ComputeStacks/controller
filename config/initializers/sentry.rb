##
# Sentry
#
# TODO: Update to latest sentry drive
#
Raven.configure do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.sanitize_fields = Rails.application.config.filter_parameters.map(&:to_s)
  config.release = "portal@#{File.read("#{Rails.root}/VERSION").strip}"
  config.environments = %w[ production ] # Default is used by clockwork
  # config.environments = %w[ default test development production ] # Default is used by clockwork
  config.logger = Logger.new(STDOUT)
  if Rails.env.production?
    config.async = lambda { |event| SentryJob.perform_later(event) }
  end
end

