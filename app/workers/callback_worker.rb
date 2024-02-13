class CallbackWorker
  include Sidekiq::Worker

  def perform(args = {})
    return if args['callback'].empty?

    event = if args['event_id']
              EventLog.find_by(id: args['event_id'])
            else
              nil
            end

    data = args['data']
    timestamp = args['timestamp']

    cb = CallbackService.new timestamp
    cb.authorization_header = args['callback']['authorization']
    cb.url = args['callback']['url']
    cb.event_log = event if event
    cb.data = data if event.nil?
    return if cb.perform

    # If we've been trying for more than 4 hours, stop.
    return if Time.at(timestamp) <= 4.hours.ago.to_time

    CallbackWorker.perform_in next_retry(timestamp), args
  end

  private

  def next_retry(timestamp)
    ts = Time.at timestamp
    # Within 5 minutes, try again in 2 minutes
    return 5.minutes if ts >= 2.minutes.ago.to_time

    # Within 10 minutes, try again in 5
    return 10.minutes if ts >= 5.minutes.ago.to_time

    # default is every 15
    15.minutes
  end

end
