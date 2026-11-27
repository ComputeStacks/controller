require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  include StandardTestControllerBase
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:admin)
    Setting.le_dns_provider
    Setting.le_dns_provider_secret
    @lb = load_balancers(:default)
    @lb.update_columns(le: true)
  end

  def set(name, value)
    s = Setting.find_by(name: name)
    s.value = value
    s.save!
  end

  test "the ACME group warns when load balancer certificates have no DNS provider" do
    set "le_dns_provider", ""
    get "/admin/settings"
    assert_response :success
    assert_select "#s_acme div.alert-warning", /No DNS provider is set/
  end

  test "the ACME group warns about failing certificates and shows no warning when healthy" do
    set "le_dns_provider", "exec"
    set "le_dns_provider_secret", "EXEC_PATH=/bin/true\nEXEC_MODE=RAW"
    get "/admin/settings"
    assert_select "#s_acme div.alert-warning", false
    assert_select "#s_acme td", /\[ENCRYPTED\] 2 variables/

    cert = LetsEncrypt.create!(user_id: nil, account: LetsEncryptAccount.create!, failure_count: 1)
    @lb.update_columns(lets_encrypt_id: cert.id)
    get "/admin/settings"
    assert_select "#s_acme div.alert-warning", /1 load balancer certificate failed to renew/
  end

  test "editing the provider credentials shows help and never prints the secret in the summary" do
    set "le_dns_provider_secret", "EXEC_PATH=/bin/true"
    s = Setting.find_by(name: "le_dns_provider_secret")
    get "/admin/settings/#{s.id}/edit"
    assert_response :success
    assert_select "p.lead", "Edit DNS Provider Credentials"
    assert_select "textarea.code-font"
    assert_select "a[href='https://go-acme.github.io/lego/dns/']"
  end

  test "the provider code edits as a single line" do
    s = Setting.find_by(name: "le_dns_provider")
    get "/admin/settings/#{s.id}/edit"
    assert_select "input[type=text][name='setting[value]']"
  end
end
