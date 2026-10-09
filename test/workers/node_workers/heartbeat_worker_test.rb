require "test_helper"
require "minitest/mock"
require "webmock"

##
# NodeWorkers::HeartbeatWorker's capacity refresh.
#
# The refresh is a best-effort fact update bolted onto the heartbeat, and everything
# below exists to prove it stays that way: GET /info enumerates images and containers
# and is materially heavier than the GET /_ping that decides online vs offline, so it
# must never be able to mark a node offline, hold up a node coming back online, or
# overwrite a good reading with a zero.
class NodeWorkers::HeartbeatWorkerTest < ActiveSupport::TestCase
  include WebMock::API

  INFO = {"NCPU" => 48, "MemTotal" => 8 * 1024 * 1024 * 1024}.freeze # 48 cores / 8192 MB
  MAINT_URL = "http://10.50.0.9:8500/v1/admin/maintenance".freeze

  setup do
    # A reconnecting node with an agent token asks the agent about maintenance first;
    # no test here may reach a real agent.
    WebMock.enable!
    WebMock.disable_net_connect!
    @node = nodes(:testone)
    @node.update!(job_status: "idle")
    @node.update_columns(primary_ip: "10.50.0.9", agent_host: nil)
    @node.reload
    [NodeWorkers::HealthCheckWorker, NodeWorkers::RecoverVolumeWorker, NodeWorkers::EvacuateNodeWorker,
      LoadBalancerWorkers::DeployConfigWorker, AgentWorkers::ChangelogPollWorker].each(&:clear)
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  test "records cpu, memory and a timestamp from a successful Docker.info" do
    freeze_time do
      up { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

      @node.reload
      assert_equal 48, @node.cpu_cores
      assert_equal 8192, @node.memory_mb
      assert_equal Time.current, @node.capacity_updated_at
    end
  end

  test "leaves the previous reading alone when Docker.info raises" do
    seed_capacity
    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_unchanged_capacity
  end

  test "leaves the previous reading alone when Docker.info reports zeros" do
    seed_capacity
    up(info: {"NCPU" => 0, "MemTotal" => 0}) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_unchanged_capacity
  end

  test "leaves the previous reading alone when Docker.info answers nothing at all" do
    seed_capacity
    up(info: {}) { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

    assert_unchanged_capacity
  end

  ##
  # The one that matters. A failing /info must not be able to strand a node in the
  # disconnected state -- that is the difference between a slow metrics call and an
  # outage that keeps a recovered node out of the fleet.
  test "a failing refresh does not disturb the offline to online transition" do
    @node.update!(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_return(reply(200, status_body(seq: 1)))

    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    @node.reload
    refute @node.disconnected, "the node must come back online regardless of /info"
    assert_equal 0, @node.failed_health_checks
    assert_not_nil @node.online_at
    assert_nil @node.cpu_cores
  end

  test "a failing refresh does not disturb the failed_health_checks reset" do
    @node.update!(disconnected: false, failed_health_checks: 1, online_at: Time.now)

    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    assert_equal 0, @node.reload.failed_health_checks
  end

  test "a failing refresh does not mark a healthy node offline" do
    up(info: ->(*) { raise "connection refused" }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.failed_health_checks
  end

  test "an offline node is not asked for its capacity" do
    called = false
    down(info: ->(*) { called = true; INFO }) do
      NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
    end

    refute called, "a Docker.info timeout on every unreachable node, every minute, is the " \
      "cost this guard exists to avoid"
    assert_equal 1, @node.reload.failed_health_checks
  end

  test "the refresh mutates a COPY of the connection options, not the shared hash" do
    before = Docker.connection.options.dup
    up { NodeWorkers::HeartbeatWorker.new.perform(@node.global_id) }

    # Docker.connection is memoised process-wide and Docker::Connection holds its
    # options hash by reference, so anything that mutates it in place is writing to
    # every other Sidekiq thread's timeouts at the same time.
    #
    # Every site that builds a Docker::Connection now dups this hash, so a whole perform
    # must leave it byte-identical.
    #
    # An earlier version of this test asserted specific timeout values instead. That was
    # order-dependent: Docker.connection.options is memoised for the life of the process,
    # so any other test that mutates it in place -- as the since-removed region migrator's
    # infra check once did -- could make these assertions pass or fail with no relation
    # to the code under test. Comparing against a snapshot taken in this test is the only
    # form that stays honest in a single-process suite.
    assert_equal before, Docker.connection.options
  end


  # --- Maintenance -----------------------------------------------------------------

  test "a node in maintenance is still pinged" do
    enter_maintenance!
    @node.update_columns(failed_health_checks: 1, online_at: 1.day.ago)
    pinged = false
    Docker.stub(:ping, ->(*) { pinged = true; "OK" }) do
      Docker.stub(:info, INFO) { perform }
    end

    assert pinged
    assert_equal 0, @node.reload.failed_health_checks
    assert_equal 48, @node.cpu_cores, "capacity refresh runs as for any reachable node"
  end

  test "a node in maintenance counts failed pings below the failure_count" do
    enter_maintenance!
    unreachable { perform }

    @node.reload
    assert_equal 1, @node.failed_health_checks
    refute @node.disconnected
  end

  test "a node in maintenance goes disconnected at the failure_count without offline! consequences" do
    enter_maintenance!
    @node.update_columns(failed_health_checks: @node.region.failure_count)

    freeze_time do
      assert_no_difference "SystemEvent.count" do
        unreachable { perform }
      end

      @node.reload
      assert @node.disconnected
      assert_equal Time.current, @node.disconnected_at
    end
    assert_empty NodeWorkers::EvacuateNodeWorker.jobs, "maintenance must never evacuate the node"
  end

  test "a node outside maintenance still raises Node Offline and evacuates" do
    @node.update_columns(failed_health_checks: @node.region.failure_count)

    assert_difference "SystemEvent.count", 1 do
      unreachable { perform }
    end

    assert @node.reload.disconnected
    assert_equal 1, NodeWorkers::EvacuateNodeWorker.jobs.size
  end

  test "a node in maintenance reconnects without recovery kicks or asking the agent" do
    enter_maintenance!
    @node.update_columns(disconnected: true, disconnected_at: 10.minutes.ago, failed_health_checks: 3)

    up { perform }

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.failed_health_checks
    assert_not_nil @node.online_at
    assert @node.maintenance
    assert_no_kicks
    assert_not_requested :get, MAINT_URL
  end

  # --- Reconnect outside maintenance --------------------------------------------------

  test "reconnect: the agent reports paused -> projected into maintenance, online, no kicks" do
    @node.update_columns(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_return(reply(200, status_body(seq: 7, local: {"since" => 1_760_000_000, "reason" => "reboot", "by" => "root"})))

    up { perform }

    @node.reload
    assert @node.maintenance, "the node's own hold is projected before it is let back"
    assert_equal "reboot", @node.maintenance_local_hold["reason"]
    assert_equal 7, @node.maintenance_seq
    refute @node.disconnected
    assert_equal 0, @node.failed_health_checks
    assert_no_kicks
  end

  test "reconnect: the agent reports not paused -> online and recovery kicks" do
    @node.update_columns(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_return(reply(200, status_body(seq: 4)))

    up { perform }

    @node.reload
    refute @node.disconnected
    refute @node.maintenance
    assert_equal 4, @node.maintenance_seq
    assert_kicked
  end

  test "reconnect: paused only by a stale controller hold while not requested -> online and recovery kicks" do
    @node.update_columns(disconnected: true, failed_health_checks: 3, maintenance_requested: false)
    stale = {"since" => 1_760_000_000, "reason" => "old request", "gen" => 3}
    stub_request(:get, MAINT_URL).to_return(reply(200, status_body(seq: 5, controller: stale)))

    up { perform }

    @node.reload
    assert_equal "old request", @node.maintenance_controller_hold["reason"], "the stale hold is still projected"
    refute @node.maintenance, "a controller hold nothing here requests is not effective maintenance"
    refute @node.disconnected
    assert_kicked
  end

  test "reconnect: 404 marks the agent unsupported and recovers immediately" do
    @node.update_columns(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_return(status: 404, body: "")

    up { perform }

    @node.reload
    refute @node.disconnected
    assert_not_nil @node.agent_maintenance_unsupported_at
    assert_kicked
  end

  test "reconnect: transport failures keep the node disconnected, then recover after three" do
    @node.update_columns(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_raise(HTTP::ConnectionError.new("refused"))

    2.times do |i|
      up { perform }
      @node.reload
      assert @node.disconnected, "attempt #{i + 1} must not recover the node"
      assert_equal i + 1, @node.maintenance_reconnect_attempts
      assert_no_kicks
    end

    assert_difference "SystemEvent.count", 1 do
      up { perform }
    end

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.maintenance_reconnect_attempts
    assert_kicked
    assert_match(/recovered without maintenance confirmation/, SystemEvent.order(:created_at).last.message)
  end

  test "reconnect: an unexpected status counts as an unconfirmed attempt" do
    @node.update_columns(disconnected: true, failed_health_checks: 3)
    stub_request(:get, MAINT_URL).to_return(status: 500, body: "")

    up { perform }

    assert @node.reload.disconnected
    assert_equal 1, @node.maintenance_reconnect_attempts
    assert_no_kicks
  end

  test "reconnect: an answer after failed attempts resets the counter" do
    @node.update_columns(disconnected: true, failed_health_checks: 3, maintenance_reconnect_attempts: 2)
    stub_request(:get, MAINT_URL).to_return(reply(200, status_body(seq: 2)))

    up { perform }

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.maintenance_reconnect_attempts
    assert_kicked
  end

  # The tokenless case shares this branch (agent_maintenance_supported?), but a saved
  # node can't be tokenless here: toggle_checkup!'s save mints one.
  test "reconnect: a recently unsupported agent recovers as before, without asking" do
    @node.update_columns(disconnected: true, failed_health_checks: 3, agent_maintenance_unsupported_at: 5.minutes.ago)

    up { perform }

    refute @node.reload.disconnected
    assert_kicked
    assert_not_requested :get, MAINT_URL
  end

  test "online! is still mark_online! plus kick_recovery!" do
    @node.update_columns(disconnected: true, failed_health_checks: 2, maintenance_reconnect_attempts: 2)
    @node.reload.online!

    @node.reload
    refute @node.disconnected
    assert_equal 0, @node.failed_health_checks
    assert_equal 0, @node.maintenance_reconnect_attempts
    assert_kicked
  end

  private

  # Node reachable: ping answers OK, so the worker treats it as online.
  def up(info: INFO, &block)
    Docker.stub(:ping, "OK") { Docker.stub(:info, info, &block) }
  end

  # Node unreachable: ping answers anything but OK.
  def down(info: INFO, &block)
    Docker.stub(:ping, "nope") { Docker.stub(:info, info, &block) }
  end

  def perform
    NodeWorkers::HeartbeatWorker.new.perform(@node.global_id)
  end

  # Ping raises, as an unreachable daemon does (the path that raises Node Offline).
  def unreachable(&block)
    Docker.stub(:ping, ->(*) { raise "connection refused" }) do
      Docker.stub(:info, INFO, &block)
    end
  end

  # Effective maintenance, via the controller request (maintenance is generated).
  def enter_maintenance!
    @node.update_columns(maintenance_requested: true, maintenance_updated: Time.current)
    @node.reload
    assert @node.maintenance
  end

  # The agent's Status body (cs-agent maintenance.Status).
  def status_body(seq:, local: nil, controller: nil, instance: "inst-1")
    body = {"paused" => !(local || controller).nil?, "controller" => controller, "local" => local, "controller_gen" => 0,
            "running" => [], "pending" => 0, "skipped_backups" => 0, "seq" => seq, "quiesce" => "quiesced",
            "sample" => nil, "instance_id" => instance}
    body["paused_since"] = 1_760_000_000 if body["paused"]
    body
  end

  def reply(status, body)
    {status: status, body: body.to_json, headers: {"Content-Type" => "application/json"}}
  end

  def assert_kicked
    assert_equal 1, NodeWorkers::HealthCheckWorker.jobs.size
    assert_equal 1, NodeWorkers::RecoverVolumeWorker.jobs.size
  end

  def assert_no_kicks
    assert_empty NodeWorkers::HealthCheckWorker.jobs
    assert_empty NodeWorkers::RecoverVolumeWorker.jobs
    assert_empty LoadBalancerWorkers::DeployConfigWorker.jobs
  end

  def seed_capacity
    @node.update_columns(cpu_cores: 16, memory_mb: 32_768, capacity_updated_at: 2.days.ago)
    @seeded_at = @node.reload.capacity_updated_at
  end

  def assert_unchanged_capacity
    @node.reload
    assert_equal 16, @node.cpu_cores
    assert_equal 32_768, @node.memory_mb
    assert_equal @seeded_at.to_i, @node.capacity_updated_at.to_i
  end
end
