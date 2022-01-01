LE_DIRECTORY = if Rails.env.production?
  'https://acme-v02.api.letsencrypt.org/directory'
elsif Rails.env.test?
  'https://localhost:14000/dir'
else
  'https://acme-staging-v02.api.letsencrypt.org/directory'
end
