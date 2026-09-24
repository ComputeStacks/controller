require "test_helper"

class LetsEncryptAccountTest < ActiveSupport::TestCase
  test "can find new account" do
    requires_external_infra! # needs an ACME server
    new_account = LetsEncryptAccount.find_or_create
    refute_nil new_account
    assert_equal LetsEncryptAccount.acme_directory, new_account.acme_directory
  end
end
