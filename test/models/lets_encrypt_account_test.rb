require 'test_helper'

##
# Test creating a LetsEncrypt Account
class LetsEncryptAccountTest < ActiveSupport::TestCase

  include AcmeTestContainerConcern

  test 'can find new account' do
    new_account = LetsEncryptAccount.find_or_create
    refute_nil new_account
  end

end
