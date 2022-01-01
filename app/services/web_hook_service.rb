class WebHookService

  attr_accessor :setting,
                :webhook_url,
                :data,
                :data_hash,
                :event

  def initialize(setting, data, webhook_url = nil)
    self.setting = setting
    self.data = nil
    self.webhook_url = webhook_url

    if setting
      if setting.name == 'webhook_billing_usage'
        self.event = EventLog.find_by(id: data)
        if event
          d = event.event_details.find_by(event_code: 'af5dbfa43bebd5f5')
          if d && !d.data.blank?
            raw_data = Oj.load(d.data)
            self.data = raw_data.to_json
          end
        end
        event.start!
      end
      self.webhook_url = setting.value
    else
      self.data = data
    end

    self.data_hash = Digest::SHA1.hexdigest data unless data.blank?
  end

  def perform
    return false if webhook_url.nil?
    return false unless webhook_url =~ URI::regexp
    result = HTTP.timeout(30).headers(accept: "application/json", content_type: "application/json; charset=UTF-8").post webhook_url, body: data
    if result.status.success?
      event.update :status, 'completed' if event
      Rails.cache.delete(data_hash) unless data_hash.blank? # Ensure cache is deleted.
      result.body.to_s
    else
      retry!(result.code)
    end
  rescue Errno::ECONNREFUSED
    retry!
  end

  private

  ##
  # Retry WebHook if it fails.
  #
  # Will try a maximum of 5 times.
  #
  # Retry sequence:
  # [`1`] 2 minutes later
  # [`2`] 15 minutes later
  # [`3..5`] Each hour
  #
  def retry!(result_code = nil)
    return false if data_hash.blank?
    cached = Rails.cache.fetch(data_hash, raw: true).to_i
    unless cached
      cache_result = Rails.cache.write(data_hash, 0, expires_in: 1.week, raw: true)
      return false unless cache_result == "OK"
      cached = Rails.cache.fetch(data_hash, raw: true).to_i
    end
    if cached > 5
      Rails.cache.delete(data_hash)
      if event
        event.event_details.create!(data: "Too many failed attempts, cancelling", event_code: '7a726cf0679e2a73')
        event.fail! 'Too many failed attempts'
      end
    else
      wait_time = case cached
                  when 0
                    2.minutes
                  when 1
                    15.minutes
                  else
                    1.hour
                  end
      if setting.nil?
        WebHookJob.set(wait: wait_time).perform_later(setting, data)
      else
        # Only pass if setting is nil
        WebHookJob.set(wait: wait_time).perform_later(setting, data, webhook_url)
      end
      Rails.cache.increment(data_hash, 1)
      if event
        event.event_details.create!(data: "Error, did not receive HTTP 2xx code from endpoint: #{result_code.nil? ? 'ERR' : result_code}. Retry in #{wait_time.to_s}", event_code: '705055b10ccc0453')
      end
    end
  end

end
