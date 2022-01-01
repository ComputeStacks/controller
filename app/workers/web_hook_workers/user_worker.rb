module WebHookWorkers
  # UserWorker handles User CRUD webhooks
  #
  # This is sent to admins based on the global webhook setting.
  class UserWorker
    include Sidekiq::Worker

    def perform(user_id)

      user = User.find_by(id: user_id)
      return if user.nil?
      setting = Setting.webhook_users
      template = "api/admin/users/show"
      if setting.value =~ URI::regexp
        data = Rabl::Renderer.new(template, obj, {format: :json}).render
        WebHookService.new(setting, data).perform
      end

    end

  end
end
