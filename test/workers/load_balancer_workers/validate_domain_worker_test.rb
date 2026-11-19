require "test_helper"
require "minitest/mock"

class LoadBalancerWorkers::ValidateDomainWorkerTest < ActiveSupport::TestCase
  setup do
    @lb = load_balancers(:default)
    @lb.update_columns(le: true, domain_valid_check: nil)
    LetsEncryptWorkers::GenerateCertWorker.clear
    # A registered account, so find_or_create never reaches an ACME server.
    @account = LetsEncryptAccount.create!(account_id: "https://acme.test/acct/1")
  end

  def validate!
    fake = Struct.new(:perform).new(true)
    LetsEncryptServices::ValidateDomainService.stub(:new, ->(*) { fake }) do
      LoadBalancerWorkers::ValidateDomainWorker.new.perform(@lb.id)
    end
    @lb.reload
  end

  def attach_cert(expires_at:, names: @lb.dns_domains.sort)
    le = LetsEncrypt.create!(user_id: nil, account: @account, expires_at: expires_at, names: names)
    @lb.update_columns(lets_encrypt_id: le.id)
  end

  test "orders a certificate when the load balancer has none" do
    validate!
    assert_not_nil @lb.domain_valid_check
    assert_equal 1, LetsEncryptWorkers::GenerateCertWorker.jobs.size
  end

  test "re-validating does not re-issue a current certificate" do
    attach_cert(expires_at: 60.days.from_now)
    validate!
    assert_not_nil @lb.domain_valid_check
    assert_empty LetsEncryptWorkers::GenerateCertWorker.jobs
  end

  test "renews a certificate that is due" do
    attach_cert(expires_at: 1.day.from_now)
    validate!
    assert_equal 1, LetsEncryptWorkers::GenerateCertWorker.jobs.size
  end

  test "re-issues when the certificate does not cover the domain" do
    attach_cert(expires_at: 60.days.from_now, names: %w[old.example *.old.example])
    validate!
    assert_equal 1, LetsEncryptWorkers::GenerateCertWorker.jobs.size
  end
end
