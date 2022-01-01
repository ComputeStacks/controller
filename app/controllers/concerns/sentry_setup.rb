module SentrySetup
  extend ActiveSupport::Concern

  included do
    before_action :set_raven_context
  end

  private

  def set_raven_context
    if current_user
      if Feature.check('collect_user_info')
        Raven.user_context(
          id: "#{ENV['APP_ID']}-#{current_user.id}",
          email: current_user.email,
          ip_address: request.remote_ip.gsub("::ffff:","")
        )
      else
        Raven.user_context(
          id: "#{ENV['APP_ID']}-#{current_user.id}"
        )
      end
    else
      Raven.user_context({})
    end
    Raven.extra_context(
      params: params.to_unsafe_h,
      url: request.url,
      extra: {
        provider: ENV['APP_ID']
      }
    )
  end

end
