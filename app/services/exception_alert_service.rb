class ExceptionAlertService

  attr_accessor :e,
                :event_code,
                :user

  def initialize(e, event_code, user = nil)
    self.e = e
    self.event_code = event_code
    self.user = user
  end

  def perform
    if SENTRY_CONFIGURED
      Raven::Context.clear!
      Raven.tags_context(event_code: event_code)
      Raven.extra_context(
        extra: {
          provider: ENV['APP_ID']
        }
      )
      if user && Feature.check('exception_user_info')
        Raven.user_context(
          id: "#{ENV['APP_ID']}-#{user.id}",
          email: user.email,
          ip_address: user.last_request_ip.to_s
        )
      elsif user
        Raven.user_context(
          id: "#{ENV['APP_ID']}-#{user.id}"
        )
      end
      Raven.capture_exception(e)
      Raven::Context.clear!
    end
    Rails.logger.warn "error=#{e.message}"
  end

end
