require "test_helper"

# Test Lets Encrypt Controller in Admin
#
# TODO: Create LetsEncrypt fixtures so we can properly test this controller.
class LetsEncryptControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin) # Admin user owns the registry.
  end

  test "can list all lets encrypt certificates" do
    get "/admin/lets_encrypt"
    assert_response :success
  end

  test "a failing load balancer certificate shows its backoff" do
    lb = load_balancers(:default)
    cert = LetsEncrypt.create!(user_id: nil, account: LetsEncryptAccount.create!)
    lb.update_columns(le: true, lets_encrypt_id: cert.id)
    get "/admin/lets_encrypt/#{cert.id}"
    assert_response :success
    assert_select "div.alert-info", /issued over DNS by cert-issuer/

    cert.update_columns(failure_count: 2, next_attempt_at: 10.minutes.from_now)
    get "/admin/lets_encrypt/#{cert.id}"
    assert_select "div.alert-danger", /2 failed attempts in a row, retry in 10 minutes/
    assert_select "div.alert-danger code", %(rake "lets_encrypt:issue_lb[#{lb.id}]")
    get "/admin/lets_encrypt"
    assert_select "span.label-danger", "2 failures"
  end
end
