require "test_helper"
require "minitest/mock"

# Runs the real cert-issuer binary against the request the real service builds.
# The ACME directory is a closed local port, so a `transient` result proves the
# binary accepted the request, the account key and the CSR (all of which are
# validated before any network access; a rejection there would be `config`).
#
# Skipped unless the binary is found: CERT_ISSUER_BIN, lib/dev/bin/cert-issuer
# (lib/dev/install-cert-issuer.sh), or `cert-issuer` on PATH.
class LetsEncryptServices::CertIssuerContractTest < ActiveSupport::TestCase
  class RecordingRunner < LetsEncryptServices::CertIssuerRunner
    attr_reader :result

    def run(**)
      @result = super
    end
  end

  def self.binary = LetsEncryptServices::CertIssuerRunner.resolve_binary

  setup do
    skip "cert-issuer binary not available (set CERT_ISSUER_BIN)" if self.class.binary.nil?
    @lb = load_balancers(:default)
    account = LetsEncryptAccount.create!
    account.update_columns(email: "ops@example.com", acme_directory: "http://127.0.0.1:9/directory")
    @cert = LetsEncrypt.create!(account: account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
  end

  test "the real binary accepts the request the service builds" do
    runner = RecordingRunner.new(binary: self.class.binary, term_grace: 5)
    outcome = Setting.stub(:le_dns_provider, "exec") do
      Setting.stub(:le_dns_provider_env, {"EXEC_PATH" => "/bin/true"}) do
        Setting.stub(:le_dns_alias_zone, "") do
          ExceptionAlertService.stub(:new, ->(*) { Struct.new(:perform).new }) do
            LetsEncryptServices::CertIssuerService.new(@cert, runner: runner).perform
          end
        end
      end
    end

    assert_equal :failed, outcome
    assert_equal "transient", runner.result.error_type, "cert-issuer said: #{runner.result.error.inspect}"
    event = @cert.event_logs.order(:id).last
    assert_equal "Transient error", event.state_reason
  end
end
