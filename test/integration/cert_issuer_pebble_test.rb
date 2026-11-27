require "test_helper"
require "minitest/mock"

# Issues a real load balancer certificate with the cert-issuer binary against
# the compose pebble (which runs with VA_ALWAYS_VALID), using the `exec` DNS
# provider with /bin/true and no propagation check.
#
#   CERT_ISSUER_PEBBLE=1 bin/rails test test/integration/cert_issuer_pebble_test.rb
#
# The binary is found the same way the app finds it (CERT_ISSUER_BIN,
# lib/dev/bin/cert-issuer, then PATH).
class CertIssuerPebbleTest < ActiveSupport::TestCase
  setup do
    @binary = LetsEncryptServices::CertIssuerRunner.resolve_binary
    skip "cert-issuer binary not available (run lib/dev/install-cert-issuer.sh)" if @binary.nil?
    skip "set CERT_ISSUER_PEBBLE=1 to run against the compose pebble" unless ENV["CERT_ISSUER_PEBBLE"] == "1"

    @lb = load_balancers(:default)
    account = LetsEncryptAccount.create!
    account.update_columns(email: "ops@example.com")
    @cert = LetsEncrypt.create!(account: account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
  end

  test "issues and stores a load balancer certificate" do
    env = {"EXEC_PATH" => "/bin/true", "CERT_ISSUER_INSECURE_SKIP_PROPAGATION_CHECK" => "1"}
    runner = LetsEncryptServices::CertIssuerRunner.new(binary: @binary, term_grace: 5)
    outcome = Setting.stub(:le_dns_provider, "exec") do
      Setting.stub(:le_dns_provider_env, env) do
        Setting.stub(:le_dns_alias_zone, "") do
          LetsEncryptServices::CertIssuerService.new(@cert, runner: runner).perform
        end
      end
    end

    event = @cert.event_logs.order(:id).last
    assert_equal :issued, outcome, event&.event_details&.pluck(:data).inspect
    @cert.reload
    crt = OpenSSL::X509::Certificate.new(@cert.crt)
    assert_equal @cert.expected_domains, @cert.names
    assert_in_delta crt.not_after.to_i, @cert.expires_at.to_i, 1
    assert @cert.account.reload.account_id.present?
  end
end
