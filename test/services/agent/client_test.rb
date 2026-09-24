require "test_helper"
require "webmock"

class Agent::ClientTest < ActiveSupport::TestCase
  # Scope WebMock to THIS test only — enabling it process-wide (via
  # webmock/minitest) would block the real HTTP that other suites make.
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!

    @project = deployments(:project_test)
    @project.consul_auth_key = "customer-bearer-key"
    # Build (don't save) a node with a fixed IP + token so the agent base URL is
    # deterministic for WebMock and resolve_node is bypassed via node:.
    @node = Node.new(label: "n", hostname: "n", primary_ip: "10.50.0.9", public_ip: "10.50.0.9")
    @node.agent_token = "node-admin-bearer"
    @base = "http://10.50.0.9:8500"
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  test "resolve_node raises NotReady when the node has no agent_token" do
    # update_columns so the mint callback doesn't hand the token straight back.
    nodes(:testone).update_columns(agent_token_encrypted: nil)
    assert_raises(Agent::Client::NotReady) do
      Agent::Client.new(@project, region: regions(:regionone))
    end
  end

  test "resolve_node raises NotReady when the region has no online node" do
    nodes(:testone).update_columns(disconnected: true)
    assert_raises(Agent::Client::NotReady) do
      Agent::Client.new(@project, region: regions(:regionone))
    end
  end

  # --- Which address the client dials -------------------------------------------

  test "dials primary_ip when agent_host is unset" do
    assert_nil @node.agent_host
    stub = stub_request(:get, "http://10.50.0.9:8500/v1/admin/changelog")
      .with(query: hash_including("since" => "0"))
      .to_return(status: 200, body: {entries: []}.to_json)

    Agent::Client.for_node(@node).changelog(since: 0)
    assert_requested stub
  end

  test "dials agent_host instead of primary_ip when it is set" do
    @node.agent_host = "100.64.79.114"
    tailnet = stub_request(:get, "http://100.64.79.114:8500/v1/admin/changelog")
      .with(query: hash_including("since" => "0"))
      .to_return(status: 200, body: {entries: []}.to_json)
    # Any call to the old address is a bug, not a fallback.
    primary = stub_request(:get, "http://10.50.0.9:8500/v1/admin/changelog")

    Agent::Client.for_node(@node).changelog(since: 0)
    assert_requested tailnet
    assert_not_requested primary
  end

  test "a blank agent_host falls back to primary_ip rather than producing a bare-port URL" do
    @node.agent_host = ""
    stub = stub_request(:get, "http://10.50.0.9:8500/v1/admin/changelog")
      .with(query: hash_including("since" => "0"))
      .to_return(status: 200, body: {entries: []}.to_json)

    Agent::Client.for_node(@node).changelog(since: 0)
    assert_requested stub
  end

  test "a hostname agent_host is dialed verbatim" do
    @node.agent_host = "node1.tailnet-abcd.ts.net"
    stub = stub_request(:get, "http://node1.tailnet-abcd.ts.net:8500/v1/admin/changelog")
      .with(query: hash_including("since" => "0"))
      .to_return(status: 200, body: {entries: []}.to_json)

    Agent::Client.for_node(@node).changelog(since: 0)
    assert_requested stub
  end

  test "put_managed self-heals once: 404 -> provision -> retry -> success" do
    managed = "#{@base}/v1/admin/projects/#{@project.id}/managed/metadata"
    tenant = "#{@base}/v1/admin/tenants/#{@project.id}"
    stub_request(:put, managed).to_return({status: 404}, {status: 200})
    tenant_stub = stub_request(:put, tenant).to_return(status: 200)

    client = Agent::Client.new(@project, node: @node)
    assert client.put_managed("metadata", "{}")

    assert_requested tenant_stub, times: 1
    assert_requested :put, managed, times: 2
  end

  test "put_managed returns false (no raise) when the agent is unreachable" do
    managed = "#{@base}/v1/admin/projects/#{@project.id}/managed/metadata"
    stub_request(:put, managed).to_raise(HTTP::ConnectionError)

    client = Agent::Client.new(@project, node: @node)
    assert_equal false, client.put_managed("metadata", "{}")
  end

  test "token_hash sent on provision is sha256 hex of the consul_auth_key" do
    tenant = "#{@base}/v1/admin/tenants/#{@project.id}"
    expected = Digest::SHA256.hexdigest("customer-bearer-key")
    stub = stub_request(:put, tenant)
      .with(body: hash_including("token_hash" => expected))
      .to_return(status: 200)

    assert Agent::Client.new(@project, node: @node).provision_tenant!
    assert_requested stub
  end

  test "changelog returns parsed entries on 200 and passes the exclusive since cursor" do
    stub = stub_request(:get, "#{@base}/v1/admin/changelog")
      .with(query: hash_including("since" => "7"))
      .to_return(status: 200, body: {entries: [{"seq" => 8, "entity_type" => "action_request"}]}.to_json)

    entries = Agent::Client.for_node(@node).changelog(since: 7)
    assert_equal 1, entries.size
    assert_equal 8, entries.first["seq"]
    assert_requested stub
  end

  test "changelog returns [] on non-2xx" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_return(status: 500)
    assert_equal [], Agent::Client.for_node(@node).changelog(since: 0)
  end

  test "changelog returns [] on a malformed body (no raise)" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_return(status: 200, body: "not json{")
    assert_equal [], Agent::Client.for_node(@node).changelog(since: 0)
  end

  test "changelog returns [] (no raise) on transport error" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_raise(HTTP::ConnectionError)
    assert_equal [], Agent::Client.for_node(@node).changelog(since: 0)
  end

  # A transport failure used to be Sentry-only. It has to raise a SystemEvent too: the
  # heartbeat pings Docker on primary_ip, so when the agent rides a separate address the
  # node keeps reporting online while projection stalls with nothing visible in the UI.
  test "changelog transport error raises a SystemEvent, deduped per node" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_raise(HTTP::ConnectionError)

    assert_difference -> { SystemEvent.where(event_code: "7dc84225816362c8").count }, 1 do
      Agent::Client.for_node(@node).changelog(since: 0)
    end

    assert_no_difference -> { SystemEvent.where(event_code: "7dc84225816362c8").count } do
      Agent::Client.for_node(@node).changelog(since: 0)
    end
  end

  # --- probe (diagnostic; must stay side-effect free) -----------------------------

  test "probe reports ok on 200 and names the address dialed" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_return(status: 200, body: {entries: []}.to_json)

    result = Agent::Client.for_node(@node).probe
    assert result[:ok]
    assert_equal 200, result[:status]
    assert_equal @base, result[:url]
  end

  test "probe distinguishes a rejected token from an address that does not answer" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_return(status: 401)
    rejected = Agent::Client.for_node(@node).probe
    assert_not rejected[:ok]
    assert_equal 401, rejected[:status]
    assert_match(/token/i, rejected[:detail])

    WebMock.reset!
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_raise(HTTP::ConnectionError)
    dead = Agent::Client.for_node(@node).probe
    assert_not dead[:ok]
    assert_nil dead[:status], "an unanswered address must not report an HTTP status"
    assert_match(/nothing answered/i, dead[:detail])
  end

  test "probe reports the override address when agent_host is set" do
    @node.agent_host = "100.64.79.114"
    stub_request(:get, "http://100.64.79.114:8500/v1/admin/changelog").with(query: hash_including("since" => "0")).to_return(status: 200, body: {entries: []}.to_json)

    assert_equal "http://100.64.79.114:8500", Agent::Client.for_node(@node).probe[:url]
  end

  test "probe fails fast without dialing when the node has no admin token" do
    @node.agent_token = nil
    unexpected = stub_request(:get, "#{@base}/v1/admin/changelog")

    result = Agent::Client.for_node(@node).probe
    assert_not result[:ok]
    assert_not_requested unexpected
  end

  # A connectivity check must never write to the event log — an operator running it while
  # diagnosing an outage would otherwise manufacture the events they are trying to read.
  test "probe raises no SystemEvent on failure, unlike changelog" do
    stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0")).to_raise(HTTP::ConnectionError)

    assert_no_difference -> { SystemEvent.count } do
      Agent::Client.for_node(@node).probe
    end
  end

  test "ack_changelog POSTs the seq and returns true on 2xx" do
    stub = stub_request(:post, "#{@base}/v1/admin/changelog/ack")
      .with(body: {seq: 42}.to_json)
      .to_return(status: 200, body: {acked: true}.to_json)
    assert_equal true, Agent::Client.for_node(@node).ack_changelog(42)
    assert_requested stub
  end

  test "ack_changelog returns false (no raise) on transport error" do
    stub_request(:post, "#{@base}/v1/admin/changelog/ack").to_raise(HTTP::ConnectionError)
    assert_equal false, Agent::Client.for_node(@node).ack_changelog(42)
  end

  test "ack_changelog returns false on non-2xx" do
    stub_request(:post, "#{@base}/v1/admin/changelog/ack").to_return(status: 500)
    assert_equal false, Agent::Client.for_node(@node).ack_changelog(42)
  end

  # --- DOWN: firewall rules ------------------------------------------------------

  test "put_firewall_rules PUTs the NatRules body and returns true on 2xx" do
    rules = {rules: [{proto: "tcp", nat: 30000, port: 3306, dest: "10.0.0.5", driver: "none"}]}
    stub = stub_request(:put, "#{@base}/v1/admin/nodes/n/firewall_rules")
      .with(body: rules.to_json)
      .to_return(status: 200)
    assert_equal true, Agent::Client.for_node(@node).put_firewall_rules("n", rules)
    assert_requested stub
  end

  test "put_firewall_rules returns false on non-2xx" do
    stub_request(:put, "#{@base}/v1/admin/nodes/n/firewall_rules").to_return(status: 400, body: {error: "bad"}.to_json)
    assert_equal false, Agent::Client.for_node(@node).put_firewall_rules("n", {rules: []})
  end

  test "put_firewall_rules returns false (no raise) on transport error" do
    stub_request(:put, "#{@base}/v1/admin/nodes/n/firewall_rules").to_raise(HTTP::ConnectionError)
    assert_equal false, Agent::Client.for_node(@node).put_firewall_rules("n", {rules: []})
  end

  test "delete_firewall_rules DELETEs the path and returns true on 2xx" do
    stub = stub_request(:delete, "#{@base}/v1/admin/nodes/n/firewall_rules").to_return(status: 200)
    assert_equal true, Agent::Client.for_node(@node).delete_firewall_rules("n")
    assert_requested stub
  end

  # --- DOWN: volume desired-state ------------------------------------------------

  test "put_volume PUTs the desired-state to the project/name path and returns true on 2xx" do
    desired = {name: "vol1", node: "n", backup: true, project_id: 5}
    stub = stub_request(:put, "#{@base}/v1/admin/projects/5/volumes/vol1")
      .with(body: desired.to_json)
      .to_return(status: 200)
    assert_equal true, Agent::Client.for_node(@node).put_volume("5", "vol1", desired)
    assert_requested stub
  end

  test "put_volume uses the detached sentinel 0 in the URL path" do
    stub = stub_request(:put, "#{@base}/v1/admin/projects/0/volumes/vol1").to_return(status: 200)
    assert_equal true, Agent::Client.for_node(@node).put_volume("0", "vol1", {name: "vol1"})
    assert_requested stub
  end

  test "put_volume returns false (no raise) on transport error" do
    stub_request(:put, "#{@base}/v1/admin/projects/5/volumes/vol1").to_raise(HTTP::ConnectionError)
    assert_equal false, Agent::Client.for_node(@node).put_volume("5", "vol1", {})
  end

  test "delete_volume DELETEs the project/name path and returns true on 2xx" do
    stub = stub_request(:delete, "#{@base}/v1/admin/projects/5/volumes/vol1").to_return(status: 200)
    assert_equal true, Agent::Client.for_node(@node).delete_volume("5", "vol1")
    assert_requested stub
  end

  # --- DOWN: task dispatch -------------------------------------------------------

  test "create_task POSTs the body and returns the task id on 202" do
    @node.datachannel_backfilled_at = Time.current
    body = {id: "abc-123", project_id: "5", name: "volume.backup", node: "n", volume: "vol1", archive: "auto", audit_id: nil, params: {source_volume: "vol1"}}
    stub = stub_request(:post, "#{@base}/v1/admin/tasks")
      .with(body: body.to_json)
      .to_return(status: 202, body: {id: "abc-123", created: true}.to_json)
    assert_equal "abc-123", Agent::Client.for_node(@node).create_task(body)
    assert_requested stub
  end

  test "create_task returns the sent id even when the 202 body is unparseable" do
    @node.datachannel_backfilled_at = Time.current
    stub_request(:post, "#{@base}/v1/admin/tasks").to_return(status: 202, body: "not json{")
    assert_equal "abc-123", Agent::Client.for_node(@node).create_task({id: "abc-123", name: "volume.backup"})
  end

  test "create_task refuses (no POST) a reserved volume.trash: id" do
    @node.datachannel_backfilled_at = Time.current
    stub = stub_request(:post, "#{@base}/v1/admin/tasks")
    assert_equal false, Agent::Client.for_node(@node).create_task({id: "volume.trash:vol1", name: "volume.trash"})
    assert_not_requested stub
  end

  test "create_task refuses + alerts (no POST) when the node is not backfilled" do
    # @node.datachannel_backfilled_at is nil (Node.new default)
    stub = stub_request(:post, "#{@base}/v1/admin/tasks")
    assert_difference "SystemEvent.count", 1 do
      assert_equal false, Agent::Client.for_node(@node).create_task({id: "abc-123", name: "volume.backup", volume: "vol1"})
    end
    assert_not_requested stub
  end

  test "create_task dedupes the un-backfilled alert within 15 minutes" do
    stub_request(:post, "#{@base}/v1/admin/tasks")
    client = Agent::Client.for_node(@node)
    assert_difference "SystemEvent.count", 1 do
      client.create_task({id: "a", name: "volume.backup"})
      client.create_task({id: "b", name: "volume.backup"})
    end
  end

  test "create_task returns false on a non-2xx dispatch" do
    @node.datachannel_backfilled_at = Time.current
    stub_request(:post, "#{@base}/v1/admin/tasks").to_return(status: 500, body: {error: "boom"}.to_json)
    assert_equal false, Agent::Client.for_node(@node).create_task({id: "abc-123", name: "volume.backup"})
  end

  test "create_task returns false (no raise) on transport error" do
    @node.datachannel_backfilled_at = Time.current
    stub_request(:post, "#{@base}/v1/admin/tasks").to_raise(HTTP::ConnectionError)
    assert_equal false, Agent::Client.for_node(@node).create_task({id: "abc-123", name: "volume.backup"})
  end
end
