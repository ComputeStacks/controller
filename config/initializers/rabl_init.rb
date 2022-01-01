require 'rabl'
Rabl.configure do |config|
  config.cache_sources = Rails.env.production?
  config.view_paths = ["#{Rails.root.to_s}/app/views"]
end