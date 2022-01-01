##
# EventLog Data
#
# @!attribute [r] id
#   @return [Integer]
#
# @!attribute data
#   @return [String]
#
# @!attribute event_code
#   `echo $(openssl rand -hex 8) | tr -d '\n' | pbcopy`
#   @return [String]
#
class EventLogDatum < ApplicationRecord

  scope :sorted, -> { order(created_at: :desc) }

  # @return [EventLog]
  belongs_to :event_log

  def formatted_data
    return data if data.blank?
    case event_code
    when 'af5dbfa43bebd5f5' # billing usage
      f_usage_data
    else
      data
    end
  rescue
    data
  end

  private

  def f_usage_data
    return data unless data[0] == '[' # Only want to try and parse json data!
    parsed = Oj.load(data)
    if parsed.count < 50
      result = []
      parsed.each do |i|
        result << {
          user: i['user'],
          subscription: {
            id: i['subscription_id'],
            subscription_product_id: i['subscription_product_id']
          },
          product: i['product'],
          container_id: i['container_id'],
          container_service_id: i['container_service_id'],
          external_id: i['external_id'],
          total: i['total'],
          qty: i['qty'],
          period: "#{i['period_start']} - #{i['period_end']}"
        }
      end
      result.to_yaml
    else
      "Output of usage data hidden due to size."
    end
  end

end
