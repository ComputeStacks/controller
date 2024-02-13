Sidekiq.strict_args!

sidekiq_redis_conf = {
  url: "redis://#{ENV['REDIS_HOST'].blank? ? 'localhost' : ENV['REDIS_HOST']}:#{ENV['REDIS_PORT'].blank? ? '6379' : ENV['REDIS_PORT']}/#{Rails.env.test? ? '8' : '6'}",
  network_timeout: 3
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
