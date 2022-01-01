class ProcessOrderWorker
  include Sidekiq::Worker

  def perform(order_id, audit_id)

    order = GlobalID::Locator.locate order_id
    audit = GlobalID::Locator.locate audit_id

    event = EventLog.create!(
      locale: 'order.provision',
      event_code: '0a3af01a3384fa10',
      audit: audit,
      status: 'pending'
    )

    order.current_event = event
    ProcessOrderService.new(order).perform

  rescue ActiveRecord::RecordNotFound
    return # Silently fail
  rescue => e
    user = nil
    if defined?(event) && event
      user = event.audit&.user
      event.event_details.create!(
        data: "Fatal Error\n#{e.message}",
        event_code: '88b1a3af8b282f4f'
      )
      event.fail! 'Fatal error'
    end
    ExceptionAlertService.new(e, '88b1a3af8b282f4f', user).perform
  end

end
