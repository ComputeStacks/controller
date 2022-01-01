# LogClient Loki for log aggregation
class LogClient < ApplicationRecord

  has_many :regions # Used to determine endpoint to pull logs from, not for container log settings.

  ##
  # Query for Loki Logs
  #
  # Example:
  #     q = {
  #       query: %Q({service_id="#{service.id}"}),
  #       step: 1,
  #       start: 1.hour.ago.to_i,
  #       end: Time.now.to_i,
  #       limit: limit
  #     }
  def query(q = {})
    return [] if q.empty?
    result = []
    rsp = call('query_range', q)
    return result unless rsp['status'] == 'success'
    return result unless rsp['data']['resultType'] == 'streams'
    rsp['data']['result'].each do |context|
      context['values'].each do |log|
        result << [
          (log[0].to_i  / 1e9),
          context['stream']['container_name'],
          log[1]
        ]
      end
    end
    result.sort.reverse
  end

  private

  ##
  # Contact Loki
  #
  # path = query_range
  def call(path, q)
    if username && password
      HTTParty.get("#{endpoint}/loki/api/v1/#{path}", query: q, format: :json, basic_auth: { username: username, password: password })
    else
      HTTParty.get("#{endpoint}/loki/api/v1/#{path}", query: q, format: :json)
    end
  end

end
