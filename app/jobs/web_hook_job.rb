class WebHookJob < ApplicationJob
  queue_as :low

  def perform(obj, data = {})
    case obj
    when User
      setting = Setting.webhook_users
      template = "api/admin/users/show"
    when BillingEvent
      setting = Setting.webhook_billing_event
      template = "api/admin/subscriptions/billing_events/show"
    when Setting # Optional way of providing raw data to a webhook.
      return false if data.blank?
      setting = obj
      # Format, only if required.
      data = data.to_json unless data.is_a?(String)
    else
      return false
    end
    if setting.value =~ URI::regexp
      data = Rabl::Renderer.new(template, obj, { format: :json }).render if data.blank?
      WebHookService.new(setting, data).perform
    end
  rescue => e
    ExceptionAlertService.new(e, '244f99e153d92fe5').perform
  end
end
