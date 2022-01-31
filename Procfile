web: bundle exec passenger start -p 3005 --max-pool-size 1 --min-instances 1 --nginx-config-template ./config/nginx.conf.erb
worker_dev: bundle exec sidekiq -C config/sidekiq/dev.yml
clock: bundle exec clockwork lib/clock.rb
