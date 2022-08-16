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
      Sentry.with_scope do |scope|
        scope.set_tags event_code: event_code
        unless CS_APP_ID.blank?
          scope.set_context(
            'extra',
            {
              provider: CS_APP_ID
            }
          )
          if user && Feature.check('exception_user_info')
            scope.set_user(
              id: "#{CS_APP_ID}-#{user.id}",
              email: user.email,
              ip_address: user.last_request_ip.to_s
            )
          elsif user
            scope.set_user( id: "#{CS_APP_ID}-#{user.id}" )
          end
        end
        Sentry.capture_exception e
      end
    end
    Rails.logger.warn "error=#{e.message}"
  end

end
