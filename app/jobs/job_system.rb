class JobSystem
  include Sidekiq::Worker
  sidekiq_options retry: false, queue: 'low'

  def perform(action, params = nil)
    case action
    when 'clean_orders'
      Order.clean!
    when 'prune_sys_events'
      EventLog.clean!
    when 'clean_stale_events'
      EventLog.clean_event_status!
    when 'clean_le_auth'
      LetsEncryptAuth.expired.delete_all
    end
  end


end
