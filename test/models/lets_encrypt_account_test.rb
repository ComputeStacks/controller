require 'test_helper'

##
# Test creating a LetsEncrypt Account
class LetsEncryptAccountTest < ActiveSupport::TestCase

  include AcmeTestContainerConcern # Only enable when you need to refresh VCR.

  test 'can find new account' do
    VCR.use_cassette("lets_encrypt/account_find") do
      new_account = LetsEncryptAccount.find_or_create
      refute_nil new_account
    end
  end

end
