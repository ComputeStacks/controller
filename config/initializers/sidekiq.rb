Sidekiq::Extensions.enable_delay!

sidekiq_redis_conf = {
  url: Rails.env.production? ? ENV["REDIS_URL"] : "redis://localhost:6379/#{Rails.env.test? ? '8' : '6'}",
  network_timeout: 3,
  driver: :hiredis
}

# unless Rails.env.production?
#   Sidekiq.configure_server do |config|
#     config.redis = sidekiq_redis_conf
#   end
#   Sidekiq.configure_client do |config|
#     config.redis = sidekiq_redis_conf
#   end
# end

Sidekiq.configure_server do |config|
  config.redis = sidekiq_redis_conf

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end

  config.server_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Server
  end

  SidekiqUniqueJobs::Server.configure(config)
end

Sidekiq.configure_client do |config|
  config.redis = sidekiq_redis_conf

  config.client_middleware do |chain|
    chain.add SidekiqUniqueJobs::Middleware::Client
  end
end
