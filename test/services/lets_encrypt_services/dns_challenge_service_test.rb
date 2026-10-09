require "test_helper"
require "minitest/mock"

class LetsEncryptServices::DnsChallengeServiceTest < ActiveSupport::TestCase
  FakeZoneClient = Struct.new(:records)

  # Stands in for Dns::ZoneRecord: records what it was asked to write and
  # marks the zone dirty, as the real one does via `state_save!`.
  class FakeRecord
    attr_reader :params, :zone

    def initialize(zone, response)
      @zone = zone
      @response = response
    end

    def create!(params)
      @params = params
      zone.update_columns(saved_state: "draft", saved_state_ts: Time.now.utc)
      @response
    end
    alias_method :update!, :create!
  end

  setup do
    @lb = load_balancers(:default)
    account = LetsEncryptAccount.create!(email: "test@example.com")
    @cert = LetsEncrypt.create!(account: account)
    @lb.update_columns(le: true, lets_encrypt_id: @cert.id)
    @event = EventLog.create!(locale: "lets_encrypt.renew", status: "running", event_code: "7a4d011518f54c6a")
  end

  def set_alias_zone(value)
    Setting.le_dns_alias_zone
    Setting.find_by(name: "le_dns_alias_zone").update_columns(value: value)
  end

  def auth_for(domain)
    LetsEncryptAuth.create!(
      certificate: @cert,
      domain: domain,
      challenge_type: "dns",
      record_name: "_acme-challenge",
      record_type: "TXT",
      record_content: "abc"
    )
  end

  # Wires `zone` so no provider is contacted. `commit` is the state_commit! result.
  # Returns a hash that collects what happened.
  def prepare_zone(zone, commit: {"success" => true}, actions: ["update_by_zone"])
    log = {locked: false, commit_locked: nil, reverted: false, commits: 0}
    zone.define_singleton_method(:available_actions) { actions }
    zone.define_singleton_method(:state_load!) { FakeZoneClient.new({"TXT" => []}) }
    zone.define_singleton_method(:with_lock) do |*args, &blk|
      log[:locked] = true
      super(*args, &blk)
    ensure
      log[:locked] = false
    end
    zone.define_singleton_method(:state_commit!) do
      log[:commits] += 1
      log[:commit_locked] = log[:locked]
      if commit["success"]
        update_columns(saved_state: nil, saved_state_ts: nil)
      end
      commit
    end
    zone.define_singleton_method(:state_revert!) do
      log[:reverted] = true
      super()
    end
    log
  end

  def run_service(auth, zone, record_response: {"success" => true})
    record = FakeRecord.new(zone, record_response)
    svc = LetsEncryptServices::DnsChallengeService.new(auth, @event)
    result = nil
    auth.stub(:dns_zone, zone) do
      Dns::ZoneRecord.stub(:new, ->(_id, z, _type) {
        assert_same zone, z
        record
      }) do
        result = svc.perform
      end
    end
    [result, svc, record]
  end

  test "alias path writes the alias name and commits inside the lock" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone)

    ok, svc, record = run_service(auth, zone)

    assert ok, svc.errors.inspect
    assert_equal "lb#{@lb.id}.acme.bar.local.", record.params[:name]
    assert_equal 1, log[:commits]
    assert log[:commit_locked], "state_commit! must run while the zone lock is held"
    refute log[:reverted]
    refute zone.commit_changes, "must not defer the push to after_update_commit"
    assert_nil zone.reload.saved_state
  end

  test "local zone path writes _acme-challenge.<domain>" do
    @lb.update_columns(domain: "apps.foo.local")
    zone = dns_zones(:user_zone)
    auth = auth_for("apps.foo.local")
    prepare_zone(zone)

    ok, svc, record = run_service(auth, zone)

    assert ok, svc.errors.inspect
    assert_equal "_acme-challenge.apps.foo.local.", record.params[:name]
  end

  test "failed push reverts the draft and records the error" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone, commit: {"success" => false, "message" => "pdns down"})

    ok, svc, _record = run_service(auth, zone)

    refute ok
    assert log[:reverted]
    assert_nil zone.reload.saved_state
    assert_includes svc.errors, "pdns down"
    detail = @event.event_details.find_by(event_code: "5ad5af9411d06754")
    assert_includes detail.data, "pdns down"
    assert_includes detail.data, "lb#{@lb.id}.acme.bar.local"
  end

  test "failed record write reverts the draft" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone)

    ok, svc, _record = run_service(auth, zone, record_response: {"success" => false, "message" => "bad record"})

    refute ok
    assert log[:reverted]
    assert_equal 0, log[:commits]
    assert_includes svc.errors, "bad record"
    assert_nil zone.reload.saved_state
  end

  test "dirty zone fails without writing" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    zone.update_columns(saved_state: "someone else's draft")
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone)

    ok, svc, record = run_service(auth, zone)

    refute ok
    assert_nil record.params
    assert_equal 0, log[:commits]
    assert_includes svc.errors, "Unable to modify zone with pending updates"
    assert @event.event_details.where(event_code: "4a46fa447bd82fef").exists?
  end

  test "zone made dirty after the pre-check is caught inside the lock" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone)
    # Another writer leaves a draft; our in-memory copy is stale.
    Dns::Zone.where(id: zone.id).update_all(saved_state: "other draft")

    ok, svc, record = run_service(auth, zone)

    refute ok
    assert_nil record.params
    assert_equal 0, log[:commits]
    refute log[:reverted]
    assert_equal "other draft", zone.reload.saved_state
    assert_includes svc.errors, "Unable to modify zone with pending updates"
  end

  test "provider without update_by_zone does not commit or revert" do
    zone = Dns::Zone.create!(name: "acme.bar.local", skip_provision_driver: true)
    set_alias_zone("acme.bar.local")
    auth = auth_for(@lb.domain)
    log = prepare_zone(zone, actions: [])

    ok, svc, _record = run_service(auth, zone)

    assert ok, svc.errors.inspect
    assert_equal 0, log[:commits]
    refute log[:reverted]
  end
end
