require 'test_helper'

# Test Lets Encrypt Controller in Admin
#
# TODO: Create LetsEncrypt fixtures so we can properly test this controller.
class LetsEncryptControllerTest < ActionDispatch::IntegrationTest

  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test 'can list all lets encrypt certificates' do
    get '/admin/lets_encrypt'
    assert_response :success
  end

end
