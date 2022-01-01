ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
Dir[Rails.root.join('lib', 'test', '**', '*.rb')].each { |file| require file }

unless ENV['RM_INFO'] # RubyMine
  require 'minitest/reporters'
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
end

require 'sidekiq/testing'
Sidekiq::Testing.fake!

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  #parallelize(workers: :number_of_processors) ## Rails 6

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  # set_fixture_class oauth_applications: 'Doorkeeper::Application'
  fixtures :all
  # set_fixture_class 'container_images/volume_params' => ContainerImage::VolumeParam

end
