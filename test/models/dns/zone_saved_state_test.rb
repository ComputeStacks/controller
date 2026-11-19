require "test_helper"

# Pending DNS edits are Marshal-dumped into dns_zones.saved_state. The dump must not
# carry the provider API client, whose Auth holds the decrypted credentials.
class Dns::ZoneSavedStateTest < ActiveSupport::TestCase
  setup do
    @driver = provision_drivers(:powerdns)
    @zone = dns_zones(:app)
    @zone.update_columns(provision_driver_id: @driver.id)
    @api_key = Secret.decrypt!(@driver.api_secret)
  end

  def remote_zone(client = @driver.service_client)
    Pdns::Dns::Zone.new(client, nil).tap { |z| z.id = "cs.local." }
  end

  test "state_save! stores no client or credentials and leaves the live zone intact" do
    live = remote_zone
    client = live.instance_variable_get(:@client)

    assert @zone.state_save!(live)

    @zone.reload
    refute_includes @zone.saved_state, @api_key
    assert_nil Marshal.load(@zone.saved_state).instance_variable_get(:@client)
    assert_same client, live.instance_variable_get(:@client)
  end

  test "state_load! re-attaches a fresh client" do
    @zone.state_save!(remote_zone)

    loaded = @zone.reload.state_load!

    client = loaded.instance_variable_get(:@client)
    assert_kind_of Pdns::Client, client
    assert_equal @driver.endpoint, client.endpoint
    assert_equal @api_key, client.auth.api_key
  end

  test "state_load! replaces the stale client in a legacy dump" do
    stale = Pdns::Client.new("http://old.example:8081/api/v1/servers", Pdns::Auth.new(0, "old", "old", "old"))
    @zone.update_columns(saved_state: Marshal.dump(remote_zone(stale)), saved_state_ts: Time.now.utc)

    loaded = @zone.state_load!

    assert_equal @driver.endpoint, loaded.instance_variable_get(:@client).endpoint
  end

  test "dns:scrub_saved_state strips credentials from legacy dumps and keeps the edits" do
    legacy = remote_zone
    legacy.records["TXT"] << Pdns::Dns::ZoneRecord.new(nil, nil, nil)
    ts = 1.hour.ago.utc.change(usec: 0)
    @zone.update_columns(saved_state: Marshal.dump(legacy), saved_state_ts: ts)
    assert_includes @zone.saved_state, @api_key

    Rails.application.load_tasks unless Rake::Task.task_defined?("dns:scrub_saved_state")
    Rake::Task["dns:scrub_saved_state"].reenable
    assert_output(/Scrubbed 1, failed 0/) { Rake::Task["dns:scrub_saved_state"].invoke }

    @zone.reload
    refute_includes @zone.saved_state, @api_key
    assert_equal 1, Marshal.load(@zone.saved_state).records["TXT"].size
    assert_equal ts, @zone.saved_state_ts
  end
end
