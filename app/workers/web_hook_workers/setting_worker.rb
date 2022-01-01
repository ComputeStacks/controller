module WebHookWorkers
  # SettingWorker is a helper to send arbitrary webhook data
  # to a webhook endpoint set in the Settings Admin.
  class SettingWorker
    include Sidekiq::Worker

    def perform(setting_id, data = {})

      return if data.empty?
      setting = Setting.find_by(id: setting_id)
      return if setting.nil?
      data = data.to_json unless data.is_a?(String)
      if setting.value =~ URI::regexp
        WebHookService.new(setting, data).perform
      end

    end

  end
end
