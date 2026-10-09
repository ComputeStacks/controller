require "test_helper"
require "webmock"

class AgentWorkers::PushMaintenanceWorkerTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    @node = nodes(:testone)
    @node.update_columns(primary_ip: "10.50.0.9", agent_host: nil, maintenance_requested: false, maintenance_reason: nil,
      maintenance_gen: 5, maintenance_override_gen: nil, maintenance_holds: {}, maintenance_seq: 0,
      agent_instance_id: nil, agent_maintenance_unsupported_at: nil)
    @node.reload
    @url = "http://10.50.0.9:8500/v1/admin/maintenance"
    AgentWorkers::PushMaintenanceWorker.jobs.clear
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  # The agent's Status body (cs-agent maintenance.Status).
  def status_body(seq:, controller: nil, local: nil, gen: 5, instance: "inst-1")
    body = {"paused" => !(controller || local).nil?, "controller" => controller, "local" => local, "controller_gen" => gen,
            "running" => [], "pending" => 0, "skipped_backups" => 0, "seq" => seq, "quiesce" => "quiesced",
            "sample" => nil, "instance_id" => instance}
    body["paused_since"] = 1_760_000_000 if body["paused"]
    body
  end

  def reply(status, body)
    {status: status, body: body.to_json, headers: {"Content-Type" => "application/json"}}
  end

  def perform
    AgentWorkers::PushMaintenanceWorker.new.perform(@node.id)
  end

  test "requested -> PUT with the reason and gen from the DB; 200 projects the body at its seq" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "kernel", maintenance_gen: 6)
    put = stub_request(:put, @url).with(body: {reason: "kernel", gen: 6}.to_json)
      .to_return(reply(200, status_body(seq: 12, gen: 6, controller: {"since" => 1_760_000_000, "reason" => "kernel", "gen" => 6})))

    perform

    assert_requested put
    @node.reload
    assert_equal 12, @node.maintenance_seq
    assert_equal "kernel", @node.maintenance_controller_hold["reason"]
    assert_equal "inst-1", @node.agent_instance_id
    refute @node.maintenance_holds.key?("seq")
    refute @node.maintenance_holds.key?("instance_id")
    refute @node.maintenance_holds.key?("running")
  end

  test "a blank reason is sent as a default, since the agent requires one" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: nil, maintenance_gen: 6)
    put = stub_request(:put, @url).with { |req| JSON.parse(req.body)["reason"].present? }
      .to_return(reply(200, status_body(seq: 1, gen: 6)))
    perform
    assert_requested put
  end

  test "not requested -> DELETE ?gen without all" do
    del = stub_request(:delete, @url).with(query: {"gen" => "5"}).to_return(reply(200, status_body(seq: 3)))
    perform
    assert_requested del
  end

  # A node hold placed `ago` before the override (negative: after it).
  def local_hold(ago:)
    {"since" => (@override_at - ago).to_i, "reason" => "forgotten", "by" => "root"}
  end

  def arm_override!(gen: 7)
    @override_at = Time.current.change(usec: 0)
    @node.update_columns(maintenance_gen: gen, maintenance_override_gen: gen, maintenance_updated: @override_at)
  end

  test "a pending override GETs first; a node hold older than the override -> DELETE ?gen&all=1, then cleared" do
    arm_override!
    get = stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6, local: local_hold(ago: 1.day))))
    del = stub_request(:delete, @url).with(query: {"gen" => "7", "all" => "1", "local_since_max" => @override_at.to_i.to_s}).to_return(reply(200, status_body(seq: 4, gen: 7)))
    perform
    assert_requested get
    assert_requested del
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert_equal 4, @node.maintenance_seq
  end

  test "a node hold placed in the same second as the override is released by it" do
    arm_override!
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6, local: local_hold(ago: 0).merge("since" => @override_at.to_i.to_s))))
    del = stub_request(:delete, @url).with(query: {"gen" => "7", "all" => "1", "local_since_max" => @override_at.to_i.to_s}).to_return(reply(200, status_body(seq: 4, gen: 7)))
    perform
    assert_requested del
  end

  test "a pending override with no node hold is retired; no DELETE without a controller hold" do
    arm_override!
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6)))
    assert_no_difference -> { SystemEvent.count } do
      perform
    end
    assert_not_requested :delete, /maintenance/
    assert_nil @node.reload.maintenance_override_gen
  end

  test "a pending override with no node hold but a controller hold -> plain DELETE, retired" do
    arm_override!
    ctrl = {"since" => 1_760_000_000, "reason" => "r", "gen" => 6}
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6, controller: ctrl)))
    del = stub_request(:delete, @url).with(query: {"gen" => "7"}).to_return(reply(200, status_body(seq: 4, gen: 7)))
    perform
    assert_requested del
    assert_nil @node.reload.maintenance_override_gen
  end

  test "a node hold placed AFTER the override is never released: plain DELETE, retired, SystemEvent" do
    arm_override!
    ctrl = {"since" => 1_760_000_000, "reason" => "r", "gen" => 6}
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6, controller: ctrl, local: local_hold(ago: -60))))
    del = stub_request(:delete, @url).with(query: {"gen" => "7"}).to_return(reply(200, status_body(seq: 4, gen: 7, local: local_hold(ago: -60))))
    assert_difference -> { SystemEvent.where("message LIKE ?", "%not applied: node hold placed after it%").count }, 1 do
      perform
    end
    assert_requested del
    assert_not_requested :delete, /all=1/
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert @node.maintenance, "the newer node hold still stands"
  end

  test "a pending override whose GET answers 404 marks the agent unsupported and drops the override" do
    arm_override!
    stub_request(:get, @url).to_return(status: 404, body: "404 page not found")
    perform
    assert_not_requested :delete, /maintenance/
    @node.reload
    assert @node.agent_maintenance_unsupported_at.present?
    assert_nil @node.maintenance_override_gen
  end

  test "a pending override whose GET fails raises so Sidekiq retries, keeping the override" do
    arm_override!
    stub_request(:get, @url).to_return(status: 500, body: "{}")
    assert_raises(AgentWorkers::PushMaintenanceWorker::DeliveryError) { perform }
    assert_not_requested :delete, /maintenance/
    assert_equal 7, @node.reload.maintenance_override_gen
  end

  test "mark_unsupported! drops a pending override" do
    arm_override!
    Nodes::MaintenanceProjection.mark_unsupported!(@node)
    assert_nil @node.reload.maintenance_override_gen
  end

  test "a stale override (override_gen != gen) is not sent as all=1" do
    @node.update_columns(maintenance_gen: 8, maintenance_override_gen: 7)
    del = stub_request(:delete, @url).with(query: {"gen" => "8"}).to_return(reply(200, status_body(seq: 4, gen: 8)))
    perform
    assert_requested del
  end

  test "412: a node hold appeared between the GET and the DELETE -> retired, SystemEvent, plain DELETE, newer hold kept" do
    arm_override!
    ctrl = {"since" => 1_760_000_000, "reason" => "r", "gen" => 6}
    newer = local_hold(ago: -5)
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 6, controller: ctrl, local: local_hold(ago: 1.day))))
    guarded = stub_request(:delete, @url).with(query: {"gen" => "7", "all" => "1", "local_since_max" => @override_at.to_i.to_s})
      .to_return(reply(412, status_body(seq: 4, gen: 6, controller: ctrl, local: newer)))
    plain = stub_request(:delete, @url).with(query: {"gen" => "7"}).to_return(reply(200, status_body(seq: 5, gen: 7, local: newer)))
    assert_difference -> { SystemEvent.where("message LIKE ?", "%not applied: node hold placed after it%").count }, 1 do
      perform
    end
    assert_requested guarded
    assert_requested plain
    @node.reload
    assert_nil @node.maintenance_override_gen
    assert_equal 5, @node.maintenance_seq
    assert @node.maintenance, "the newer node hold still stands"
  end

  test "409 jumps the gen past the agent's, re-arms the override, alerts, and re-pushes once" do
    arm_override!
    stub_request(:get, @url).to_return(reply(200, status_body(seq: 3, gen: 20, local: local_hold(ago: 1.day))))
    stub_request(:delete, @url).with(query: {"gen" => "7", "all" => "1", "local_since_max" => @override_at.to_i.to_s}).to_return(reply(409, status_body(seq: 4, gen: 20)))

    assert_difference -> { SystemEvent.count }, 1 do
      perform
    end

    @node.reload
    assert_equal 21, @node.maintenance_gen
    assert_equal 21, @node.maintenance_override_gen, "the override stays pending at the new gen"
    assert_equal 1, AgentWorkers::PushMaintenanceWorker.jobs.size
    assert_equal [@node.id, true], AgentWorkers::PushMaintenanceWorker.jobs.first["args"]

    # The re-push conflicting again does not loop.
    AgentWorkers::PushMaintenanceWorker.jobs.clear
    stub_request(:delete, @url).with(query: {"gen" => "21", "all" => "1", "local_since_max" => @override_at.to_i.to_s}).to_return(reply(409, status_body(seq: 4, gen: 30)))
    AgentWorkers::PushMaintenanceWorker.new.perform(@node.id, true)
    assert_empty AgentWorkers::PushMaintenanceWorker.jobs
  end

  test "409 without a pending override leaves override_gen alone" do
    @node.update_columns(maintenance_requested: true, maintenance_reason: "x", maintenance_gen: 3)
    stub_request(:put, @url).to_return(reply(409, status_body(seq: 4, gen: 9)))
    perform
    @node.reload
    assert_equal 10, @node.maintenance_gen
    assert_nil @node.maintenance_override_gen
  end

  test "404 marks the agent unsupported and clears projected holds" do
    @node.update_columns(maintenance_holds: {"local" => {"since" => 1, "reason" => "x"}}, maintenance_seq: 9, agent_instance_id: "old")
    stub_request(:delete, @url).with(query: hash_including("gen" => "5")).to_return(status: 404, body: "404 page not found")

    perform

    @node.reload
    assert @node.agent_maintenance_unsupported_at.present?
    assert_equal({}, @node.maintenance_holds)
    assert_equal 0, @node.maintenance_seq
    assert_nil @node.agent_instance_id
    assert_equal false, @node.maintenance
  end

  test "skips a node whose agent was marked unsupported within the hour" do
    @node.update_columns(agent_maintenance_unsupported_at: 10.minutes.ago)
    perform
    assert_not_requested :any, /8500/
  end

  test "retries an agent last marked unsupported over an hour ago" do
    @node.update_columns(agent_maintenance_unsupported_at: 2.hours.ago)
    del = stub_request(:delete, @url).with(query: hash_including("gen" => "5")).to_return(reply(200, status_body(seq: 1)))
    perform
    assert_requested del
  end

  test "skips a node without an agent token" do
    @node.update_columns(agent_token_encrypted: nil)
    perform
    assert_not_requested :any, /8500/
  end

  test "a transport error raises so Sidekiq retries" do
    stub_request(:delete, @url).with(query: hash_including("gen" => "5")).to_raise(HTTP::ConnectionError.new("refused"))
    assert_raises(HTTP::ConnectionError) { perform }
  end

  test "a 5xx raises so Sidekiq retries" do
    stub_request(:delete, @url).with(query: hash_including("gen" => "5")).to_return(status: 500, body: "{}")
    assert_raises(AgentWorkers::PushMaintenanceWorker::DeliveryError) { perform }
  end

  test "a lock miss re-enqueues in 5 s without calling the agent" do
    # A separate session: transactional tests pin one shared connection, and an
    # advisory lock is re-entrant within a session.
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: cfg[:username], password: cfg[:password])
    begin
      other.exec("SELECT pg_advisory_lock(#{Nodes::MaintenanceProjection::ADVISORY_LOCK_CLASS}, #{@node.id})")
      perform
      assert_not_requested :any, /8500/
      job = AgentWorkers::PushMaintenanceWorker.jobs.last
      assert_equal @node.id, job["args"].first
      assert_in_delta 5.seconds.from_now.to_f, job["at"], 2
    ensure
      other.close
    end
  end

  test "retries exhausted raises a SystemEvent naming the node" do
    job = {"args" => [@node.id]}
    assert_difference -> { SystemEvent.where("message LIKE ?", "%not delivered to #{@node.label}%").count }, 1 do
      AgentWorkers::PushMaintenanceWorker.sidekiq_retries_exhausted_block.call(job, StandardError.new("boom"))
    end
  end
end
