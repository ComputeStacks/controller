##
# Rack::Attack
#
# Docs: https://github.com/kickstarter/rack-attack/wiki/Example-Configuration
#
class Rack::Attack

  throttle('req/ip', limit: 2500, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets') || req.xhr?
  end

  throttle('logins/ip', limit: 10, period: 20.seconds) do |req|
    if (req.path == '/login' || req.path == '/users/login') && req.post?
      req.ip
    end
  end

  throttle("logins/api_key", limit: 80, period: 20.seconds) do |req|
    if req.path == '/api/auth' && req.post?
      # return the email if present, nil otherwise
      req.params['api_key'].presence
    end
  end

  throttle("logins/email", limit: 10, period: 20.seconds) do |req|
    if (req.path == '/login' || req.path == '/users/login') && req.post?
      # return the email if present, nil otherwise
      req.params['email'].presence
    end
  end

end
Rack::Attack.throttled_response_retry_after_header = true
Rack::Attack.throttled_response = lambda do |env|
  match_data = env['rack.attack.match_data']
  now = match_data[:epoch_time]

  headers = {
      'RateLimit-Limit' => match_data[:limit].to_s,
      'RateLimit-Remaining' => '0',
      'RateLimit-Reset' => (now + (match_data[:period] - now % match_data[:period])).to_s
  }

  [ 429, headers, ["Throttled\n"]]
end
