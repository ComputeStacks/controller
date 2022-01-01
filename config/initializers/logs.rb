Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::KeyValue.new
  config.lograge.custom_options = lambda do |event|
    exceptions = %w(controller action format id)
    opts = {
      customer: ENV['APP_ID'],
      params: event.payload[:params].except(*exceptions),
      timestamp: Time.now.utc.iso8601
    }
    opts[:user] = event.payload[:user] if event.payload[:user]
    opts[:ip] = event.payload[:ip] if event.payload[:ip]
    opts[:uuid] = event.payload[:uuid] if event.payload[:uuid]
    opts[:appid] = event.payload[:appid] if event.payload[:appid]
    opts
  end
  config.lograge.ignore_custom = lambda do |event|
    return true if event.payload[:poll] # see ApplicationController for how this is defined.
  end
end
