require "test_helper"
require "minitest/mock"

class LetsEncryptWorkers::GenerateCertWorkerAliasTest < ActiveSupport::TestCase
  class FakeChallenge
    attr_reader :validation_requests

    def initialize
      @validation_requests = 0
    end

    def record_name = "_acme-challenge"

    def record_type = "TXT"

    def record_content = "token"

    def status = "pending"

    def request_validation
      @validation_requests += 1
      true
    end

    def reload = self
  end

  FakeAuthorization = Struct.new(:domain, :wildcard, :dns, :status, :expires)
  FakeOrder = Struct.new(:authorizations)
  FakeClient = Struct.new(:order) do
    def new_order(identifiers:)
      order
    end
  end
  FakeAccount = Struct.new(:client)
  FakeCheck = Struct.new(:errors) do
    def perform = false
  end

  setup do
    Setting.le_auto_enabled?
    @lb = load_balancers(:default)
    account = LetsEncryptAccount.create!(email: "test@example.com")
    @cert = LetsEncrypt.create!(account: account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
    Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    Setting.le_dns_alias_zone
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: "acme.bar.local")

    @challenge = FakeChallenge.new
    wildcard = FakeAuthorization.new(@lb.domain, true, @challenge, "pending", 1.week.from_now)
    client = FakeClient.new(FakeOrder.new([wildcard]))
    @cert.define_singleton_method(:has_default_acme_provider?) { true }
    @cert.define_singleton_method(:account) { FakeAccount.new(client) }
    @cert.define_singleton_method(:can_provision?) { |_event| true }
  end

  test "missing alias CNAME fails the event without writing TXT or contacting the CA" do
    check = FakeCheck.new(["Missing DNS alias record. Please add this record at your DNS provider: x"])
    check_lb = nil
    challenge_called = false

    LetsEncrypt.stub(:find_by, @cert) do
      LetsEncryptServices::DnsAliasCheckService.stub(:new, ->(lb, **) {
        check_lb = lb
        check
      }) do
        LetsEncryptServices::DnsChallengeService.stub(:new, ->(*) {
          challenge_called = true
          raise "TXT must not be written"
        }) do
          LetsEncryptWorkers::GenerateCertWorker.new.perform(@cert.id)
        end
      end
    end

    assert_equal @lb, check_lb
    refute challenge_called
    assert_equal 0, @challenge.validation_requests
    event = @cert.event_logs.order(:id).last
    assert_equal "failed", event.status
    detail = event.event_details.find_by(event_code: "7774fe2fd9ee5ae0")
    assert detail
    assert_includes detail.data, "Missing DNS alias record"
  end

  test "alias zone configured but not a local zone names the alias zone" do
    Dns::Zone.find_by(name: "acme.bar.local").destroy

    LetsEncrypt.stub(:find_by, @cert) do
      LetsEncryptWorkers::GenerateCertWorker.new.perform(@cert.id)
    end

    assert_equal 0, @challenge.validation_requests
    event = @cert.event_logs.order(:id).last
    assert_equal "failed", event.status
    detail = event.event_details.find_by(event_code: "0994c35516f37636")
    assert_includes detail.data, "DNS alias zone acme.bar.local does not exist"
  end

  test "no local zone and no alias zone configured says so" do
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: "")

    LetsEncrypt.stub(:find_by, @cert) do
      LetsEncryptWorkers::GenerateCertWorker.new.perform(@cert.id)
    end

    assert_equal 0, @challenge.validation_requests
    detail = @cert.event_logs.order(:id).last.event_details.find_by(event_code: "0994c35516f37636")
    assert_includes detail.data, "no DNS alias zone is configured"
  end
end
