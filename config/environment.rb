# Load the Rails application.
require_relative 'application'
require './lib/core_ext/array'
require './lib/core_ext/string'

# Initialize the Rails application.
Rails.application.initialize!

# Wipe out default gem i18n.
I18n.load_path = I18n.load_path.delete_if { |i| i =~ /gems/ }

# I18n.load_path = Dir[Rails.root.join('config', 'locales', '*.{rb,yml}')]
# I18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]
