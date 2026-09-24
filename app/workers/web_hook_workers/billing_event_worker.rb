module WebHookWorkers
  class BillingEventWorker
    include Sidekiq::Worker

    def perform(billing_event_id)
      billing_event = BillingEvent.find_by(id: billing_event_id)
      return if billing_event.nil?
      setting = Setting.webhook_billing_event
      template = "api/admin/subscriptions/billing_events/show"

      if setting.value&.match?(URI::DEFAULT_PARSER.make_regexp)
        data = Rabl::Renderer.new(template, billing_event, {format: :json}).render
        WebHookService.new(setting, data).perform
      end
    end
  end
end
