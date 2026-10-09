require "test_helper"
require "webmock"

class AgentWorkers::MaintenanceDriftWorkerTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    @node = nodes(:testone)
    @node.update_columns(primary_ip: "10.50.0.9", agent_host: nil, disconnected: false, maintenance_requested: false,
      maintenance_reason: nil, maintenance_gen: 5, maintenance_override_gen: nil, maintenance_holds: {},
      maintenance_seq: 0, maintenance_status: {}, agent_instance_id: nil, agent_maintenance_unsupported_at: nil)
    @node.reload
    @url = "http://10.50.0.9:8500/v1/admin/maintenance"
    AgentWorkers::MaintenanceDriftWorker.jobs.clear
    AgentWorkers::PushMaintenanceWorker.jobs.clear
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  def status_body(seq:, controller: nil, local: nil, gen: 5, instance: "inst-1", running: [], pending: 0, quiesce: "quiesced")
    body = {"paused" => !(controller || local).nil?, "controller" => controller, "local" => local, "controller_gen" => gen,
            "running" => running, "pending" => pending, "skipped_backups" => 0, "seq" => seq, "quiesce" => quiesce,
            "sample" => nil, "instance_id" => instance}
    body["paused_since"] = 1_760_000_000 if body["paused"]
    body
  end

  def reply(status, body)
    {status: status, body: body.to_json, headers: {"Content-Type" => "application/json"}}
  end

  def stub_get(body, status: 200)
    stub_request(:get, @url).to_return(reply(status, body))
  end

  def drift
    AgentWorkers::MaintenanceDriftWorker.new.perform(@node.id)
  end

  def hold(gen:, since: Time.now.to_i, reason: "r")
    {"since" => since, "reason" => reason, "gen" => gen}
  end

  # --- fan-out --------------------------------------------------------------------

  test "fans out over every node with a token, disconnected included, skipping recently-unsupported ones" do
    @node.update_columns(disconnected: true)
    AgentWorkers::MaintenanceDriftWorker.new.perform
    assert_equal [[@node.id]], AgentWorkers::MaintenanceDriftWorker.jobs.map { |j| j["args"] }

    AgentWorkers::MaintenanceDriftWorker.jobs.clear
    @node.update_columns(agent_maintenance_unsupported_at: 5.minutes.ago)
    AgentWorkers::MaintenanceDriftWorker.new.perform
    assert_empty AgentWorkers::MaintenanceDriftWorker.jobs

    @node.update_columns(agent_maintenance_unsupported_at: nil, agent_token_encrypted: nil)
    AgentWorkers::MaintenanceDriftWorker.new.perform
    assert_empty AgentWorkers::MaintenanceDriftWorker.jobs
  end

  test "a disconnected node is still read and projected" do
    @node.update_columns(disconnected: true)
    stub_get(status_body(seq: 3, local: {"since" => 1, "reason" => "docker", "by" => "root"}))
    drift
    @node.reload
    assert_equal 3, @node.maintenance_seq
    assert @node.maintenance
  end

  # --- projection + status ----------------------------------------------------------

  test "projects the body at its seq and records maintenance_status" do
    running = [{"id" => "t1", "kind" => "volume.backup", "volume" => "v", "started_at" => 1}]
    stub_get(status_body(seq: 8, running: running, pending: 2, quiesce: "busy"))
    drift
    @node.reload
    assert_equal 8, @node.maintenance_seq
    assert_equal running, @node.maintenance_status["running"]
    assert_equal 2, @node.maintenance_status["pending"]
    assert_equal "busy", @node.maintenance_status["quiesce"]
    assert @node.maintenance_status["observed_at"].present?
    assert_nil @node.maintenance_status["mismatch_since"]
  end

  test "a stale seq does not regress the projection" do
    @node.update_columns(maintenance_seq: 10, maintenance_holds: {"local" => {"since" => 1, "reason" => "x"}}, agent_instance_id: "inst-1")
    stub_get(status_body(seq: 9))
    drift
    @node.reload
    assert_equal 10, @node.maintenance_seq
    assert @node.maintenance_local_hold
  end

  test "an instance_id change resets the seq guard" do
    @node.update_columns(maintenance_seq: 500, maintenance_holds: {"local" => {"since" => 1, "reason" => "x"}}, agent_instance_id: "old")
    stub_get(status_body(seq: 2, instance: "new"))
    drift
    @node.reload
    assert_equal "new", @node.agent_instance_id
    assert_equal 2, @node.maintenance_seq
    assert_nil @node.maintenance_local_hold
  end

  test "a nil instance_id is adopted silently" do
    stub_get(status_body(seq: 1, instance: "first"))
    assert_no_difference -> { SystemEvent.count } do
      drift
    end
    assert_equal "first", @node.reload.agent_instance_id
  end

  test "an unreachable agent is silent for the cycle and keeps the last status" do
    @node.update_columns(maintenance_status: {"quiesce" => "busy", "observed_at" => "2026-01-01T00:00:00Z"})
    stub_request(:get, @url).to_raise(HTTP::TimeoutError.new("timed out"))
    assert_no_difference -> { SystemEvent.count } do
      assert_equal :unreachable, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
    end
    assert_equal "2026-01-01T00:00:00Z", @node.reload.maintenance_status["observed_at"]
  end

  # --- reconcile ------------------------------------------------------------------

  test "requested but no controller hold -> PUT" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 6)
    stub_get(status_body(seq: 1))
    put = stub_request(:put, @url).with(body: {reason: "kernel", gen: 6}.to_json)
      .to_return(reply(200, status_body(seq: 2, gen: 6, controller: hold(gen: 6))))
    drift
    assert_requested put
    @node.reload
    assert_equal 2, @node.maintenance_seq
    assert_nil @node.maintenance_status["mismatch_since"], "the reconcile's own answer settled it"
  end

  test "requested with a controller hold at an older gen -> PUT" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 9)
    stub_get(status_body(seq: 1, controller: hold(gen: 6), gen: 6))
    put = stub_request(:put, @url).to_return(reply(200, status_body(seq: 1, gen: 9, controller: hold(gen: 9))))
    drift
    assert_requested put
  end

  test "requested with a current controller hold -> nothing sent" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 6)
    stub_get(status_body(seq: 1, controller: hold(gen: 6), gen: 6))
    drift
    assert_not_requested :put, @url
    assert_not_requested :delete, /maintenance/
  end

  test "not requested but a controller hold -> DELETE" do
    stub_get(status_body(seq: 1, controller: hold(gen: 4), gen: 4))
    del = stub_request(:delete, @url).with(query: {"gen" => "5"}).to_return(reply(200, status_body(seq: 2)))
    drift
    assert_requested del
  end

  def arm_override!(gen: 7)
    @override_at = Time.current.change(usec: 0)
    @node.update_columns(maintenance_gen: gen, maintenance_override_gen: gen, maintenance_updated: @override_at)
  end

  test "a pending override is honored: DELETE all=1 for a node hold placed before it, from this pass' GET" do
    arm_override!
    stub_get(status_body(seq: 1, local: {"since" => @override_at.to_i - 3600, "reason" => "forgotten", "by" => "root"}, gen: 6))
    del = stub_request(:delete, @url).with(query: {"gen" => "7", "all" => "1", "local_since_max" => @override_at.to_i.to_s}).to_return(reply(200, status_body(seq: 2, gen: 7)))
    drift
    assert_requested del
    assert_requested :get, @url, times: 1 # deliver reuses the drift body
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert_equal false, @node.maintenance
    assert_nil @node.maintenance_status["mismatch_since"]
  end

  test "a node hold placed after a pending override is not released: retired with a SystemEvent" do
    arm_override!
    stub_get(status_body(seq: 1, local: {"since" => @override_at.to_i + 60, "reason" => "docker-upgrade", "by" => "ops"}, gen: 6))
    assert_difference -> { SystemEvent.where("message LIKE ?", "%not applied: node hold placed after it%").count }, 1 do
      drift
    end
    assert_not_requested :delete, /maintenance/
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert @node.maintenance
  end

  test "a node hold without a readable since is never released by an override" do
    arm_override!
    stub_get(status_body(seq: 1, local: {"since" => "yesterday", "reason" => "x"}, gen: 6))
    drift
    assert_not_requested :delete, /maintenance/
    assert_nil @node.reload.maintenance_override_gen
  end

  # The code review's scenario: an override requested while the agent was unreachable
  # must not wipe a node hold placed days later.
  test "an override with nothing to release is retired, and never wipes a later node hold" do
    NodeServices::MaintenanceRequestService.new(@node, on: false, override_all: true).perform
    @node.reload
    assert_equal @node.maintenance_gen, @node.maintenance_override_gen

    # The operator cleared the node hold themselves; the agent reports none.
    stub_get(status_body(seq: 10, gen: 5))
    assert_no_difference -> { SystemEvent.where("message LIKE ?", "%not applied%").count } do
      drift
    end
    assert_not_requested :delete, /maintenance/
    assert_nil @node.reload.maintenance_override_gen, "retired: nothing left to do"

    # Days later: a fresh, legitimate node hold.
    WebMock.reset!
    stub_get(status_body(seq: 20, gen: @node.maintenance_gen, local: {"since" => 2.days.from_now.to_i, "reason" => "docker-upgrade", "by" => "ops"}))
    travel 2.days + 1.minute do
      drift
    end
    assert_not_requested :delete, /maintenance/
    assert @node.reload.maintenance
  end

  test "an override is cleared when the agent answers 404" do
    arm_override!
    stub_request(:get, @url).to_return(status: 404, body: "404 page not found")
    drift
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert @node.agent_maintenance_unsupported_at.present?
  end

  test "a local hold alone with no override pending is left alone" do
    stub_get(status_body(seq: 1, local: {"since" => 1, "reason" => "docker", "by" => "root"}))
    drift
    assert_not_requested :delete, /maintenance/
  end

  test "404 marks the agent unsupported and alerts once a day while requested" do
    @node.update_columns(maintenance_requested: true)
    stub_request(:get, @url).to_return(status: 404, body: "404 page not found")
    assert_difference -> { SystemEvent.where("message LIKE ?", "%older than 3.4.0%").count }, 1 do
      assert_equal :unsupported, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
      assert_equal :unsupported, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
    end
    assert @node.reload.agent_maintenance_unsupported_at.present?
  end

  test "refresh! is a live read: a 200 lifts the unsupported back-off" do
    @node.update_columns(agent_maintenance_unsupported_at: 5.minutes.ago)
    stub_get(status_body(seq: 1))
    assert_equal :ok, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
    assert_nil @node.reload.agent_maintenance_unsupported_at
  end

  # --- alerts ----------------------------------------------------------------------

  test "a mismatch alerts only when it survives into the next cycle" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 6)
    stub_get(status_body(seq: 1))
    stub_request(:put, @url).to_return(status: 503, body: "{}") # the reconcile keeps failing

    assert_no_difference -> { SystemEvent.where("message LIKE ?", "Maintenance mismatch%").count } do
      drift
    end
    since = @node.reload.maintenance_status["mismatch_since"]
    assert since.present?

    assert_difference -> { SystemEvent.where("message LIKE ?", "Maintenance mismatch%").count }, 1 do
      drift
    end
    assert_equal since, @node.reload.maintenance_status["mismatch_since"], "keeps the first sighting"

    # Resolved -> cleared.
    WebMock.reset!
    stub_get(status_body(seq: 2, controller: hold(gen: 6), gen: 6))
    drift
    assert_nil @node.reload.maintenance_status["mismatch_since"]
  end

  test "a hold older than 12 h alerts once per 12 h, naming the holder and reason" do
    old = 13.hours.ago.to_i
    stub_get(status_body(seq: 1, local: {"since" => old, "reason" => "docker-upgrade", "by" => "root"}))
    assert_difference -> { SystemEvent.where("message LIKE ?", "Maintenance hold older than 12 hours%").count }, 1 do
      drift
      drift
    end
    msg = SystemEvent.where("message LIKE ?", "Maintenance hold older than 12 hours%").last.message
    assert_includes msg, "node by root"
    assert_includes msg, "docker-upgrade"
  end

  test "a fresh hold does not alert" do
    stub_get(status_body(seq: 1, local: {"since" => 1.hour.ago.to_i, "reason" => "docker", "by" => "root"}))
    assert_no_difference -> { SystemEvent.count } do
      drift
    end
  end

  test "refresh! returns :no_token for a node without a token, and :locked when the lock is held" do
    stub_get(status_body(seq: 1))
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: cfg[:username], password: cfg[:password])
    begin
      other.exec("SELECT pg_advisory_lock(#{Nodes::MaintenanceProjection::ADVISORY_LOCK_CLASS}, #{@node.id})")
      assert_equal :locked, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node)
    ensure
      other.close
    end
    assert_not_requested :get, @url

    @node.update_columns(agent_token_encrypted: nil)
    assert_equal :no_token, AgentWorkers::MaintenanceDriftWorker.new.refresh!(@node.reload)
  end
end
