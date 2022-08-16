module SentrySetup
  extend ActiveSupport::Concern

  included do
    before_action :set_sentry_context
  end

  private

  def set_sentry_context
    return unless SENTRY_CONFIGURED
    Sentry.configure_scope do |scope|
      if current_user
        if Feature.check('collect_user_info')
          scope.set_user(
            id: "#{ENV['APP_ID']}-#{current_user.id}",
            email: current_user.email,
            ip_address: request.remote_ip.gsub("::ffff:","")
          )
        else
          scope.set_user id: "#{ENV['APP_ID']}-#{current_user.id}"
        end
      end
      scope.set_context(
        'extra',
        {
          params: params.to_unsafe_h,
          url: request.url,
          provider: ENV['APP_ID']
        }
      )
    end
  end

end
