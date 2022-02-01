class SentryJob < ApplicationJob
  queue_as :default
  def perform(event)
    return unless SENTRY_CONFIGURED
    Raven.send_event(event)
  end
end
