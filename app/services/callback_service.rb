##
# API Events can include a callback
#
# @param authorization_header
#   The right side of the auth header.
#   This can be:
#     - `Bearer abcdefg1234`
#     - `Token abcdefg1234`
#     - `abcdefg1234`
#   @return [String]
#
# @!attribute timestamp
#   Time.now.to_i
#   Used for tracking retries.
#   @return [Integer]
#
class CallbackService

  attr_accessor :authorization_header,
                :url,
                :data,
                :event_log,
                :timestamp


  # @param [Integer] timestamp | epoch
  # @param [EventLog,nil] event_log
  def initialize(timestamp, event_log = nil)
    self.authorization_header = nil
    self.url = nil
    self.timestamp = timestamp
    self.data = {}
    self.event_log = event_log
    data_from_event! if event_log
  end

  def perform
    return false if url.blank?
    data_from_event! if event_log

    result = HTTP.timeout(30)
                 .headers(callback_headers)
                 .post(url, json: data)
    result.status.success?
  end

  private

  def data_from_event!
    self.data = {
      'timestamp' => timestamp,
      'success' => event_log.success?,
      'data' => event_log.event_details.map(&:data)
    }
  end

  def callback_headers
    h = { "accept" =>  "application/json" }
    h['Authorization'] = authorization_header unless authorization_header.blank?
    h
  end

end
