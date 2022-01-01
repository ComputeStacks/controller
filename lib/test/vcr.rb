require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.ignore_request do |request|
    u = URI(request.uri)

    ##
    # consul has dynamic data, so we can't store that.
    local_consul = %w(127.0.0.1 localhost).include?(u.host) && u.port == 8500 # consul running locally
    remote_consul = u.port == 8501 # consul running on a node

    local_consul || remote_consul
  end
end
