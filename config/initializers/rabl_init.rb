require "rabl"
Rabl.configure do |config|
  config.cache_sources = Rails.env.production?
  config.view_paths = ["#{Rails.root}/app/views"]
end
