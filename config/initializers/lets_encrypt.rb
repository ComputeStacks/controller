LE_DIRECTORY = if Rails.env.production?
  'https://acme-v02.api.letsencrypt.org/directory'
elsif Rails.env.test?
  "https://#{ENV['DOCKER_IP']}:#{ENV['ACME_API_PORT']}/dir"
else
  'https://acme-staging-v02.api.letsencrypt.org/directory'
end
