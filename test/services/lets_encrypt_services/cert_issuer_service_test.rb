require "test_helper"
require "minitest/mock"

class LetsEncryptServices::CertIssuerServiceTest < ActiveSupport::TestCase
  Result = LetsEncryptServices::CertIssuerRunner::Result
  Service = LetsEncryptServices::CertIssuerService

  class StubRunner
    attr_reader :calls

    def initialize(*results, &block)
      @results = results
      @block = block
      @calls = []
    end

    def run(request:, env:, timeout:)
      @calls << {request: request, env: env, timeout: timeout}
      return @block.call(request) if @block
      (@results.size > 1) ? @results.shift : @results.first
    end
  end

  class FakeAlert
    def initialize(log, e, code)
      @log = log
      @e = e
      @code = code
    end

    def perform = @log << [@e, @code]
  end

  FakeCheck = Struct.new(:ok, :failure, :errors) do
    def perform = ok
  end

  # Dev's .envrc may set RESOLVER_LIST; tests start without it.
  teardown { ENV["RESOLVER_LIST"] = @old_resolver_list }

  setup do
    @old_resolver_list = ENV.delete("RESOLVER_LIST")
    @lb = load_balancers(:default)
    @account = LetsEncryptAccount.create!
    @account.update_columns(email: "ops@example.com")
    @cert = LetsEncrypt.create!(account: @account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
    @alerts = []
    @env = {"EXEC_PATH" => "/bin/true"}
  end

  def ok_result(names: @cert.expected_domains.map(&:downcase), not_after: "2027-02-01T00:00:00Z", **extra)
    Result.new(error_type: nil, payload: {
      "version" => 1, "status" => "ok",
      "account_url" => "https://ca.test/acct/1",
      "certificate_pem" => "-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----\n",
      "certificate_url" => "https://ca.test/cert/1",
      "names" => names, "not_before" => "2026-11-01T00:00:00Z", "not_after" => not_after
    }.merge(extra.transform_keys(&:to_s)), exit_status: 0, stderr_tail: "")
  end

  def error_result(type, stderr_tail: "", **error)
    Result.new(error_type: type, payload: {
      "version" => 1, "status" => "error",
      "error" => {"type" => type, "message" => "#{type} happened"}.merge(error.transform_keys(&:to_s))
    }, exit_status: 13, stderr_tail: stderr_tail)
  end

  # Stubs the DNS settings and captures ExceptionAlertService calls.
  def with_settings(provider: "exec", env: @env, alias_zone: "", &block)
    env_value = env.is_a?(Exception) ? ->(*) { raise env } : ->(*) { env }
    alerts = @alerts
    Setting.stub(:le_dns_provider, provider) do
      Setting.stub(:le_dns_provider_env, env_value) do
        Setting.stub(:le_dns_alias_zone, alias_zone) do
          ExceptionAlertService.stub(:new, ->(e, code, *) { FakeAlert.new(alerts, e, code) }, &block)
        end
      end
    end
  end

  def perform(runner, **opts)
    with_settings(**opts.slice(:provider, :env, :alias_zone)) do
      Service.new(@cert, runner: runner, **opts.slice(:event, :sweep)).perform
    end
  end

  def last_event = @cert.event_logs.order(:id).last

  def deep_values(h)
    h.values.flat_map { |v| v.is_a?(Hash) ? deep_values(v) : [v] }
  end

  test "request matches the contract" do
    runner = StubRunner.new(ok_result)
    perform(runner)
    call = runner.calls.first
    req = call[:request]
    assert_equal %i[version directory_url account csr_pem dns deadline_seconds tls_insecure_skip_verify].sort, req.keys.sort
    assert_equal 1, req[:version]
    assert_equal @account.acme_directory, req[:directory_url]
    assert_equal %i[key_pem email].sort, req[:account].keys.sort
    assert_equal @account.private_key.to_pem, req[:account][:key_pem]
    assert_equal "ops@example.com", req[:account][:email]
    assert_equal({provider: "exec"}, req[:dns])
    assert_equal Service::DEADLINE, req[:deadline_seconds]
    assert_equal true, req[:tls_insecure_skip_verify]
    refute deep_values(req).any?(&:nil?)
    assert_equal @env, call[:env]
    assert_equal Service::HARD_TIMEOUT, call[:timeout]
    assert_equal 540, Service::HARD_TIMEOUT
  end

  test "resolvers are sent only when RESOLVER_LIST is set" do
    ENV["RESOLVER_LIST"] = "9.9.9.9, 2620:fe::fe"
    runner = StubRunner.new(ok_result)
    perform(runner)
    assert_equal({provider: "exec", resolvers: ["9.9.9.9:#{NS_PORT}", "[2620:fe::fe]:#{NS_PORT}"]}, runner.calls.first[:request][:dns])
  end

  test "email is omitted unless it has exactly one @" do
    @account.update_columns(email: "")
    runner = StubRunner.new(ok_result)
    perform(runner)
    refute runner.calls.first[:request][:account].key?(:email)
  end

  test "EAB is sent only when configured and the account uses the default directory" do
    runner = StubRunner.new(ok_result)
    LetsEncryptAccount.stub(:acme_uses_eab?, true) do
      Setting.stub(:acme_kid, "kid-1") do
        Setting.stub(:acme_hmac_key, "aG1hYw") do
          perform(runner)
          @account.update_columns(acme_directory: "https://other.test/dir")
          @cert.reload
          perform(runner)
        end
      end
    end
    assert_equal({kid: "kid-1", hmac_key: "aG1hYw"}, runner.calls[0][:request][:account][:eab])
    refute runner.calls[1][:request][:account].key?(:eab)
  end

  test "CSR carries the common name and every expected domain" do
    runner = StubRunner.new(ok_result)
    perform(runner)
    csr = OpenSSL::X509::Request.new(runner.calls.first[:request][:csr_pem])
    assert csr.verify(csr.public_key)
    assert_includes csr.subject.to_s, "CN=#{@cert.select_common_name}"
    san = csr.attributes.find { |a| a.oid == "extReq" }.value.value.first.value.find { |e| e.value.first.value == "subjectAltName" }
    names = OpenSSL::X509::Extension.new(san).value.split(",").map { |n| n.strip.delete_prefix("DNS:") }
    assert_equal ["*.a.app", "a.app"], names.sort
  end

  test "success stores the requested names, expiry and certificate, and clears backoff" do
    @lb.update_columns(domain: "A.app")
    @cert.update_columns(failure_count: 3, next_attempt_at: 1.hour.from_now)
    @account.update_columns(account_id: nil)
    runner = StubRunner.new(ok_result(account_created: true))
    assert_equal :issued, perform(runner)
    @cert.reload
    assert_equal ["*.A.app", "A.app"], @cert.names
    assert_equal Time.iso8601("2027-02-01T00:00:00Z"), @cert.expires_at
    assert_includes @cert.crt, "BEGIN CERTIFICATE"
    assert_equal 0, @cert.failure_count
    assert_nil @cert.next_attempt_at
    assert_equal "https://ca.test/acct/1", @account.reload.account_id
    assert_equal "completed", last_event.status
    assert last_event.event_details.find_by(event_code: Service::ACCOUNT_CREATED_CODE)
  end

  test "an existing account id is left alone" do
    @account.update_columns(account_id: "https://ca.test/acct/existing")
    perform(StubRunner.new(ok_result))
    assert_equal "https://ca.test/acct/existing", @account.reload.account_id
  end

  test "config error fails the event and backs off 6 hours" do
    freeze_time do
      assert_equal :failed, perform(StubRunner.new(error_result("config", acme_problem: {"detail" => "bad eab"})))
      @cert.reload
      assert_equal 1, @cert.failure_count
      assert_equal 6.hours.from_now, @cert.next_attempt_at
      assert_equal "failed", last_event.status
      assert_equal "Configuration error", last_event.state_reason
      data = last_event.event_details.pluck(:data)
      assert_includes data, "config happened"
      assert_includes data, "ACME: bad eab"
    end
  end

  test "validation failure writes one detail per domain and backs off 6 hours" do
    freeze_time do
      result = error_result("validation_failed", domains: {"*.a.app" => {"type" => "validation_failed", "message" => "NXDOMAIN"}})
      perform(StubRunner.new(result))
      assert_equal 6.hours.from_now, @cert.reload.next_attempt_at
      assert_equal "Validation failed", last_event.state_reason
      assert_includes last_event.event_details.pluck(:data), "*.a.app: NXDOMAIN"
    end
  end

  test "rate limit honors retry_after, else waits an hour, and does not alert" do
    freeze_time do
      perform(StubRunner.new(error_result("rate_limited", retry_after: 2.hours.from_now.utc.iso8601)))
      assert_equal 2.hours.from_now, @cert.reload.next_attempt_at
      assert_equal "Rate limited", last_event.state_reason
      perform(StubRunner.new(error_result("rate_limited")))
      assert_equal 1.hour.from_now, @cert.reload.next_attempt_at
      perform(StubRunner.new(error_result("rate_limited", retry_after: 1.hour.ago.utc.iso8601)))
      assert_equal 1.hour.from_now, @cert.reload.next_attempt_at
      assert_equal 3, @cert.failure_count
    end
    assert_empty @alerts
  end

  test "transient failures double from 5 minutes up to an hour" do
    freeze_time do
      [5, 10, 20, 40, 60, 60].each_with_index do |minutes, i|
        perform(StubRunner.new(error_result("transient")))
        @cert.reload
        assert_equal i + 1, @cert.failure_count
        assert_equal minutes.minutes.from_now, @cert.next_attempt_at
      end
      assert_equal "Transient error", last_event.state_reason
    end
  end

  test "internal error alerts and uses the transient schedule" do
    freeze_time do
      perform(StubRunner.new(error_result("internal", stderr_tail: "panic: boom")))
      assert_equal 5.minutes.from_now, @cert.reload.next_attempt_at
    end
    assert_equal 1, @alerts.size
    assert_equal Service::INTERNAL_CODE, @alerts.first[1]
    assert_includes @alerts.first[0].message, "panic: boom"
    assert_equal "Fatal Error", last_event.state_reason
  end

  test "an unexpected exception fails the event, alerts and backs off" do
    runner = StubRunner.new { raise "kaboom" }
    freeze_time do
      assert_equal :failed, perform(runner)
      assert_equal 5.minutes.from_now, @cert.reload.next_attempt_at
    end
    assert_equal 1, @cert.failure_count
    assert_equal "failed", last_event.status
    assert last_event.event_details.find_by(event_code: Service::UNEXPECTED_CODE)
    assert_equal [Service::UNEXPECTED_CODE], @alerts.map(&:last)
  end

  test "a bad not_after takes the unexpected path" do
    perform(StubRunner.new(ok_result(not_after: "not a time")))
    assert_equal "failed", last_event.status
    assert_equal 1, @cert.reload.failure_count
  end

  test "sweep skips certs that are not due" do
    @cert.update_columns(expires_at: 80.days.from_now, names: @cert.expected_domains)
    runner = StubRunner.new(ok_result)
    assert_equal :skipped, perform(runner, sweep: true)
    assert_empty runner.calls
    assert_empty @cert.event_logs
  end

  test "sweep re-checks renewal under the lock" do
    LetsEncrypt.where(id: @cert.id).update_all(expires_at: 80.days.from_now, names: @cert.expected_domains)
    assert @cert.can_renew?, "in-memory copy is stale and still due"
    runner = StubRunner.new(ok_result)
    assert_equal :skipped, perform(runner, sweep: true)
    assert_empty runner.calls
    assert_empty @cert.event_logs
    assert_equal 0, @cert.reload.failure_count
  end

  test "sweep skips when no provider is configured, without backoff" do
    runner = StubRunner.new(ok_result)
    assert_equal :skipped, perform(runner, sweep: true, provider: "")
    assert_empty runner.calls
    assert_empty @cert.event_logs
    assert_equal 0, @cert.reload.failure_count
  end

  test "sweep skips while backing off; other runs ignore the backoff" do
    @cert.update_columns(next_attempt_at: 10.minutes.from_now, failure_count: 2)
    runner = StubRunner.new(ok_result)
    assert_equal :skipped, perform(runner, sweep: true)
    assert_empty runner.calls
    assert_equal :issued, perform(runner)
    assert_equal 1, runner.calls.size
  end

  test "non-sweep run without a provider fails without backoff" do
    runner = StubRunner.new(ok_result)
    assert_equal :failed, perform(runner, provider: "")
    assert_empty runner.calls
    assert_equal "failed", last_event.status
    assert_includes last_event.event_details.first.data, "le_dns_provider"
    assert_equal 0, @cert.reload.failure_count
    assert_nil @cert.next_attempt_at
  end

  test "malformed provider credentials fail with a 6 hour backoff" do
    freeze_time do
      runner = StubRunner.new(ok_result)
      perform(runner, env: ArgumentError.new("line 2: expected KEY=value"))
      assert_empty runner.calls
      assert_equal 6.hours.from_now, @cert.reload.next_attempt_at
      assert_includes last_event.event_details.first.data, "line 2"
    end
  end

  test "another running event skips the run and cancels the passed event" do
    other = EventLog.create!(locale: "lets_encrypt.generate", status: "running", event_code: "x")
    other.lets_encrypts << @cert
    mine = EventLog.create!(locale: "load_balancers.generate_lets_encrypt", status: "running", event_code: "f68bcf5786036bf2")
    runner = StubRunner.new(ok_result)
    assert_equal :skipped, perform(runner, event: mine)
    assert_empty runner.calls
    assert_equal "cancelled", mine.reload.status
    assert_equal 0, @cert.reload.failure_count
  end

  test "a passed event is linked to the cert and used" do
    mine = EventLog.create!(locale: "load_balancers.generate_lets_encrypt", status: "running", event_code: "f68bcf5786036bf2")
    assert_equal :issued, perform(StubRunner.new(ok_result), event: mine)
    assert_includes @cert.event_logs.reload, mine
    assert_equal 1, @cert.event_logs.count
    assert_equal "completed", mine.reload.status
  end

  test "the passed event being already linked is fine" do
    mine = EventLog.create!(locale: "load_balancers.generate_lets_encrypt", status: "running", event_code: "f68bcf5786036bf2")
    mine.lets_encrypts << @cert
    assert_equal :issued, perform(StubRunner.new(ok_result), event: mine)
  end

  test "alias preflight runs only when an alias zone is configured" do
    called = []
    LetsEncryptServices::DnsAliasCheckService.stub(:new, ->(lb, **) {
      called << lb
      FakeCheck.new(true, nil, [])
    }) do
      perform(StubRunner.new(ok_result))
      assert_empty called
      perform(StubRunner.new(ok_result), alias_zone: "acme.example.net")
      assert_equal [@lb], called
    end
  end

  test "missing alias fails before cert-issuer with a 6 hour backoff" do
    runner = StubRunner.new(ok_result)
    freeze_time do
      LetsEncryptServices::DnsAliasCheckService.stub(:new, ->(*) { FakeCheck.new(false, :missing_record, ["Missing DNS alias record"]) }) do
        perform(runner, alias_zone: "acme.example.net")
      end
      assert_equal 6.hours.from_now, @cert.reload.next_attempt_at
    end
    assert_empty runner.calls
    assert_equal "DNS Alias Missing", last_event.state_reason
    assert_equal "Missing DNS alias record", last_event.event_details.find_by(event_code: Service::ALIAS_MISSING_CODE).data
  end

  test "alias lookup error uses the transient schedule" do
    freeze_time do
      LetsEncryptServices::DnsAliasCheckService.stub(:new, ->(*) { FakeCheck.new(false, :lookup_error, ["DNS lookup failed"]) }) do
        perform(StubRunner.new(ok_result), alias_zone: "acme.example.net")
      end
      assert_equal 5.minutes.from_now, @cert.reload.next_attempt_at
    end
  end
end
