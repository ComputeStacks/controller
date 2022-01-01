require 'test_helper'

class User::ApiCredentialTest < ActiveSupport::TestCase
  
  test "can create valid api credential" do

    user = User.first
    api_credential = user.api_credentials.new(name: 'my test credential')

    assert api_credential.save
    assert_equal api_credential.name, 'my test credential'
    assert api_credential.valid_password?(api_credential.generated_password)

    # Now try again with a fresh record

    auth = User::ApiCredential.find_by_username(api_credential.username)
    assert_not_nil auth
    assert auth.valid_password?(api_credential.generated_password)

  end

end
