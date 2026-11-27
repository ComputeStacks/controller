require "test_helper"
require "minitest/mock"

class LetsEncryptWorkers::GenerateCertWorkerLbTest < ActiveSupport::TestCase
  Worker = LetsEncryptWorkers::GenerateCertWorker

  class FakeService
    attr_reader :calls

    def initialize(outcome, &on_perform)
      @outcome = outcome
      @on_perform = on_perform
      @calls = []
    end

    def build(cert, event:, sweep:)
      @calls << {cert: cert, event: event, sweep: sweep}
      self
    end

    def perform
      @on_perform&.call
      @outcome
    end
  end

  class FakeAlert
    def initialize(log, e)
      @log = log
      @e = e
    end

    def perform = @log << @e.message
  end

  FakeChallenge = Struct.new(:status)
  FakeAuthorization = Struct.new(:domain, :wildcard, :status, :expires) do
    def http = FakeChallenge.new("pending")
  end
  FakeOrder = Struct.new(:authorizations)
  FakeClient = Struct.new(:order) do
    def new_order(identifiers:) = order
  end
  FakeAccount = Struct.new(:client)

  setup do
    Setting.le_auto_enabled?
    @lb = load_balancers(:default)
    @cert = LetsEncrypt.create!(account: LetsEncryptAccount.create!)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
  end

  def running_event(locale = "load_balancers.generate_lets_encrypt")
    EventLog.create!(locale: locale, status: "running", event_code: "f68bcf5786036bf2")
  end

  def with_service(svc, &block)
    LetsEncryptServices::CertIssuerService.stub(:new, svc.method(:build), &block)
  end

  def sweep(provider: "exec")
    enqueued = []
    alerts = []
    Setting.stub(:le_dns_provider, provider) do
      ExceptionAlertService.stub(:new, ->(e, *) { FakeAlert.new(alerts, e) }) do
        Worker.stub(:perform_async, ->(id, *) { enqueued << id }) do
          Worker.new.perform(nil)
        end
      end
    end
    [enqueued, alerts]
  end

  test "an LB cert with an event goes to the cert-issuer service" do
    event = running_event
    svc = FakeService.new(:issued) { event.done! }
    result = with_service(svc) { Worker.new.perform(@cert.id, event.id) }
    assert_equal true, result
    assert_equal [{cert: @cert, event: event, sweep: false}], svc.calls
    assert_equal "completed", event.reload.status
  end

  test "an LB cert enqueued by the sweep runs as a sweep" do
    svc = FakeService.new(:skipped)
    result = with_service(svc) { Worker.new.perform(@cert.id) }
    assert_equal false, result
    assert_equal [{cert: @cert, event: nil, sweep: true}], svc.calls
  end

  test "an event linked to the cert by the LB service does not block its own run" do
    event = running_event
    event.lets_encrypts << @cert
    svc = FakeService.new(:issued) { event.done! }
    with_service(svc) { Worker.new.perform(@cert.id, event.id) }
    assert_equal 1, svc.calls.size
  end

  test "the worker does not double-fail an event the service finished" do
    event = running_event
    svc = FakeService.new(:failed) { event.fail!("Transient error") }
    with_service(svc) { Worker.new.perform(@cert.id, event.id) }
    assert_equal "Transient error", event.reload.state_reason
  end

  test "the worker copes with the service deleting the event" do
    event = running_event
    svc = FakeService.new(:skipped) { event.destroy }
    with_service(svc) { Worker.new.perform(@cert.id, event.id) }
    refute EventLog.exists?(event.id)
  end

  test "sweep enqueues a due LB cert when a provider is configured" do
    enqueued, = sweep
    assert_includes enqueued, @cert.id
  end

  test "sweep skips LB certs without a provider" do
    enqueued, = sweep(provider: "")
    refute_includes enqueued, @cert.id
  end

  test "sweep skips LB certs that are backing off, and enqueues once it passes" do
    @cert.update_columns(next_attempt_at: 5.minutes.from_now, failure_count: 1)
    enqueued, = sweep
    refute_includes enqueued, @cert.id
    @cert.update_columns(next_attempt_at: 1.minute.ago)
    enqueued, = sweep
    assert_includes enqueued, @cert.id
  end

  test "sweep skips LB certs with a running event" do
    running_event("lets_encrypt.renew").lets_encrypts << @cert
    enqueued, = sweep
    refute_includes enqueued, @cert.id
  end

  test "expiring LB cert that keeps failing alerts once per day" do
    @cert.update_columns(expires_at: 5.days.from_now, failure_count: 4, next_attempt_at: 10.minutes.from_now)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      _, alerts = sweep
      assert_equal 1, alerts.size
      assert_includes alerts.first, @lb.domain
      assert_includes alerts.first, "4 time(s)"
      _, alerts = sweep
      assert_empty alerts
      travel 25.hours do
        _, alerts = sweep
        assert_equal 1, alerts.size
      end
    end
  end

  test "expiring LB cert alerts when no provider is configured" do
    @cert.update_columns(expires_at: 5.days.from_now, failure_count: 0)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      enqueued, alerts = sweep(provider: "")
      refute_includes enqueued, @cert.id
      assert_equal 1, alerts.size
      assert_includes alerts.first, "no DNS provider"
    end
  end

  test "no expiry alert without failures or with time to spare" do
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      @cert.update_columns(expires_at: 5.days.from_now, failure_count: 0)
      _, alerts = sweep
      assert_empty alerts
      @cert.update_columns(expires_at: 20.days.from_now, failure_count: 3, names: ["x"])
      _, alerts = sweep
      assert_empty alerts
    end
  end

  test "a wildcard name on a non-LB cert fails the event" do
    @lb.update_columns(lets_encrypt_id: nil)
    order = FakeOrder.new([FakeAuthorization.new("example.com", true, "pending", 1.week.from_now)])
    @cert.define_singleton_method(:account) { FakeAccount.new(FakeClient.new(order)) }
    @cert.define_singleton_method(:has_default_acme_provider?) { true }
    @cert.define_singleton_method(:expected_domains) { ["*.example.com"] }
    @cert.define_singleton_method(:can_provision?) { |_event| true }
    LetsEncrypt.stub(:find_by, @cert) do
      Worker.new.perform(@cert.id)
    end
    event = @cert.event_logs.order(:id).last
    assert_equal "failed", event.status
    assert_equal "Wildcard not supported", event.state_reason
    assert_includes event.event_details.pluck(:data).join, "only supported on load balancer certificates"
  end
end
