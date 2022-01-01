Rails.application.config.session_store :cookie_store, key: '_computestacks_session', expire_after: 3.days
#Rails.application.config.session_store :active_record_store, key: '_computestacks_session'
# Rails.application.config.session_store :redis_store, {
#   expire_after: 6.hours,
#   key: "_#{ENV['APP_ID']}_session",
#   servers: [{
#     host: ENV['REDIS_HOST'],
#     port: 6379,
#     db: 10,
#     namespace: 'session'
#   }]
# }
