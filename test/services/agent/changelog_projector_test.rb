require "test_helper"
require "webmock"

class Agent::ChangelogProjectorTest < ActiveSupport::TestCase
  include WebMock::API

  setup do
    WebMock.enable!
    WebMock.disable_net_connect!
    ContainerActionWorkers::DispatchWorker.clear

    @saved = ContainerActionRegistry.instance_variable_get(:@handlers).dup
    ContainerActionRegistry.register("test_action", "FakeActionHandler")
    FakeActionHandler.reset!

    @project = deployments(:project_test)
    @node = nodes(:testone)
    @node.update!(primary_ip: "10.50.0.9", public_ip: "10.50.0.9")
    @node.agent_token = "tok"
    @node.save!
    @node.update_columns(changelog_cursor: 0, changelog_acked: 0)
    @base = "http://10.50.0.9:8500"
    stub_ack # every successful pass acks; stub it so WebMock doesn't reject the POST
  end

  teardown do
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
    ContainerActionRegistry.instance_variable_set(:@handlers, @saved)
  end

  def stub_changelog(entries, since: 0, high_water: nil)
    body = {entries: entries}
    body[:high_water] = high_water if high_water
    stub_request(:get, "#{@base}/v1/admin/changelog")
      .with(query: hash_including("since" => since.to_s))
      .to_return(status: 200, body: body.to_json, headers: {"Content-Type" => "application/json"})
  end

  # A node_maintenance entry as the agent writes it: the payload has NO seq.
  def maintenance_entry(seq, local: nil, controller: nil, instance: "inst-1")
    {"seq" => seq, "entity_type" => "node_maintenance", "entity_id" => "node", "op" => "upsert",
     "payload" => {"paused" => !(local || controller).nil?, "controller" => controller, "local" => local,
                   "paused_since" => ((local || controller) ? 1_760_000_000 : nil), "skipped_backups" => 0,
                   "sample" => nil, "instance_id" => instance, "controller_gen" => 0}}
  end

  def stub_ack
    stub_request(:post, "#{@base}/v1/admin/changelog/ack")
      .to_return(status: 200, body: {acked: true}.to_json, headers: {"Content-Type" => "application/json"})
  end

  # --- entry builders ------------------------------------------------------------

  def entry(seq, action_id, type: "test_action", params: {"foo" => "bar"}, entity_type: "action_request")
    {"seq" => seq, "entity_type" => entity_type, "entity_id" => action_id, "project_id" => @project.id.to_s, "op" => "upsert",
     "payload" => {"id" => action_id, "project_id" => @project.id.to_s, "action_type" => type, "params" => params, "status" => "pending"}}
  end

  def volume_echo(seq, name = "v")
    {"seq" => seq, "entity_type" => "volume", "entity_id" => name, "project_id" => @project.id.to_s, "op" => "upsert",
     "payload" => {"name" => name, "project_id" => @project.id.to_s, "config" => {}}}
  end

  def task_entry(seq, id, status: "pending", name: "volume.backup", result: nil, volume: "vol-uuid", audit_id: nil, op: "upsert", project_id: @project.id.to_s)
    payload = {"id" => id, "name" => name, "status" => status, "volume" => volume,
               "project_id" => project_id, "audit_id" => audit_id, "result" => result}
    {"seq" => seq, "entity_type" => "task", "entity_id" => id, "project_id" => project_id,
     "op" => op, "payload" => (op == "delete" ? nil : payload)}
  end

  def repo_entry(seq, name, op: "upsert", archives: ["a1"], size_on_disk: 100, total_size: 200)
    payload = (op == "delete") ? nil : {"name" => name, "size_on_disk" => size_on_disk, "total_size" => total_size,
                                        "archives" => archives, "updated_at" => 1_700_000_000}
    {"seq" => seq, "entity_type" => "repository", "entity_id" => name, "op" => op, "payload" => payload}
  end

  # --- action_request (pilot path, unchanged) ------------------------------------

  test "projects action_request rows and advances the cursor past no-op echoes" do
    stub_changelog([entry(1, "a1"), entry(2, "a2"), volume_echo(3)])
    Agent::ChangelogProjector.new(@node).call
    assert_equal 2, ContainerActionRequest.where(action_id: %w[a1 a2]).count
    assert_equal "received", ContainerActionRequest.find_by(action_id: "a1").status
    assert_equal({"foo" => "bar"}, ContainerActionRequest.find_by(action_id: "a1").params)
    assert_equal 3, @node.reload.changelog_cursor
  end

  test "empty batch does not crash and leaves cursor unchanged" do
    @node.update_columns(changelog_cursor: 5, changelog_acked: 5)
    stub_changelog([], since: 5)
    assert_nothing_raised { Agent::ChangelogProjector.new(@node).call }
    assert_equal 5, @node.reload.changelog_cursor
  end

  test "unregistered action_type is projected as unhandled" do
    stub_changelog([entry(1, "u1", type: "mystery_action")])
    Agent::ChangelogProjector.new(@node).call
    assert_equal "unhandled", ContainerActionRequest.find_by(action_id: "u1").status
  end

  test "oversized params rejected at projection" do
    big = {"mode" => "paths", "paths" => ["/" + ("x" * 20_000)]}
    stub_changelog([entry(1, "big", params: big)])
    Agent::ChangelogProjector.new(@node).call
    assert_equal "rejected", ContainerActionRequest.find_by(action_id: "big").status
  end

  test "skips no-id entries, delete tombstones, and blank action_type; cursor still advances" do
    blank = {"seq" => 3, "entity_type" => "action_request", "entity_id" => "blank", "op" => "upsert",
             "payload" => {"id" => "blank", "action_type" => "", "params" => {}}}
    stub_changelog([entry(1, nil), entry(2, "del").merge("op" => "delete"), blank, entry(4, "keep")])
    Agent::ChangelogProjector.new(@node).call
    assert ContainerActionRequest.exists?(action_id: "keep")
    refute ContainerActionRequest.exists?(action_id: "del")
    refute ContainerActionRequest.exists?(action_id: "blank")
    assert_equal 4, @node.reload.changelog_cursor
  end

  # --- task projection -----------------------------------------------------------

  test "projects task rows and updates snapshots by id" do
    stub_changelog([task_entry(1, "t1", status: "pending", audit_id: 42)])
    Agent::ChangelogProjector.new(@node).call
    t = AgentTask.find("t1")
    assert_equal "pending", t.status
    assert_equal "volume.backup", t.name
    assert_equal 42, t.audit_id
    assert_equal @node.id, t.node_id

    stub_changelog([task_entry(2, "t1", status: "running")], since: 1)
    Agent::ChangelogProjector.new(@node).call
    assert_equal "running", AgentTask.find("t1").status
  end

  test "collapses multiple snapshots of one task id in a batch to the highest seq" do
    stub_changelog([task_entry(1, "t1", status: "pending"),
                    task_entry(2, "t1", status: "running"),
                    task_entry(3, "t1", status: "completed")])
    assert_nothing_raised { Agent::ChangelogProjector.new(@node).call }
    assert_equal 1, AgentTask.where(id: "t1").count
    assert_equal "completed", AgentTask.find("t1").status
    assert_equal 3, @node.reload.changelog_cursor
  end

  test "a reused task id transitions again at a higher seq (volume.trash re-issue)" do
    tid = "volume.trash:vol-x"
    stub_changelog([task_entry(1, tid, name: "volume.trash", status: "failed", volume: "vol-x")])
    Agent::ChangelogProjector.new(@node).call
    assert_equal "failed", AgentTask.find(tid).status

    # controller re-issues the DELETE; the agent resets the SAME id and completes it at
    # higher seqs — the projection must follow (no "terminal is forever" trap).
    stub_changelog([task_entry(3, tid, name: "volume.trash", status: "completed", volume: "vol-x")], since: 1)
    Agent::ChangelogProjector.new(@node).call
    assert_equal "completed", AgentTask.find(tid).status
  end

  test "task delete tombstone is ignored (history kept)" do
    stub_changelog([task_entry(1, "t1", status: "completed")])
    Agent::ChangelogProjector.new(@node).call
    stub_changelog([task_entry(2, "t1", op: "delete")], since: 1)
    Agent::ChangelogProjector.new(@node).call
    assert AgentTask.exists?(id: "t1")
    assert_equal 2, @node.reload.changelog_cursor
  end

  # --- repository projection -----------------------------------------------------

  test "projects repository rows" do
    stub_changelog([repo_entry(1, "vol-uuid", archives: %w[auto-1 auto-2], size_on_disk: 111, total_size: 222)])
    Agent::ChangelogProjector.new(@node).call
    r = AgentRepository.find_by(name: "vol-uuid")
    assert_equal 111, r.size_on_disk
    assert_equal 222, r.total_size
    assert_equal %w[auto-1 auto-2], r.archives
  end

  test "repository delete tombstone removes the row" do
    AgentRepository.create!(name: "vol-uuid", size_on_disk: 1, total_size: 2, archives: [])
    stub_changelog([repo_entry(1, "vol-uuid", op: "delete")])
    Agent::ChangelogProjector.new(@node).call
    refute AgentRepository.exists?(name: "vol-uuid")
  end

  test "collapses multiple repository snapshots of one name in a batch (no upsert conflict)" do
    stub_changelog([repo_entry(1, "vol-x", size_on_disk: 1), repo_entry(2, "vol-x", size_on_disk: 2)])
    assert_nothing_raised { Agent::ChangelogProjector.new(@node).call }
    assert_equal 2, AgentRepository.find_by(name: "vol-x").size_on_disk
  end

  test "a repository delete wins over an earlier upsert in the same batch" do
    stub_changelog([repo_entry(1, "vol-x"), repo_entry(2, "vol-x", op: "delete")])
    Agent::ChangelogProjector.new(@node).call
    refute AgentRepository.exists?(name: "vol-x")
  end

  # --- unknown / unprojectable guard ---------------------------------------------

  test "unknown entity_type halts the cursor below it and alerts" do
    unknown = {"seq" => 2, "entity_type" => "mystery", "entity_id" => "x", "op" => "upsert", "payload" => {}}
    stub_changelog([task_entry(1, "t1", status: "completed"), unknown, task_entry(3, "t3", status: "completed")])
    assert_difference "SystemEvent.count", 1 do
      Agent::ChangelogProjector.new(@node).call
    end
    assert AgentTask.exists?(id: "t1")
    refute AgentTask.exists?(id: "t3") # after the halt, not projected
    assert_equal 1, @node.reload.changelog_cursor
    assert_equal 1, @node.changelog_acked
  end

  test "task missing status halts the cursor below it" do
    bad = {"seq" => 2, "entity_type" => "task", "entity_id" => "tbad", "op" => "upsert",
           "payload" => {"id" => "tbad", "name" => "volume.backup"}}
    stub_changelog([task_entry(1, "t1", status: "completed"), bad])
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, @node.reload.changelog_cursor
    refute AgentTask.exists?(id: "tbad")
  end

  test "an unknown type at the head of the batch leaves the cursor unmoved" do
    unknown = {"seq" => 1, "entity_type" => "mystery", "entity_id" => "x", "op" => "upsert", "payload" => {}}
    stub_changelog([unknown])
    Agent::ChangelogProjector.new(@node).call
    assert_equal 0, @node.reload.changelog_cursor
  end

  # --- ack -----------------------------------------------------------------------

  test "acks the cursor after a successful projection and advances changelog_acked" do
    stub_changelog([task_entry(1, "t1", status: "completed")])
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, @node.reload.changelog_acked
    assert_requested :post, "#{@base}/v1/admin/changelog/ack", body: {seq: 1}.to_json
  end

  test "empty batch flushes a pending ack" do
    @node.update_columns(changelog_cursor: 5, changelog_acked: 0)
    stub_changelog([], since: 5)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 5, @node.reload.changelog_acked
    assert_requested :post, "#{@base}/v1/admin/changelog/ack", body: {seq: 5}.to_json
  end

  test "does not re-ack when the cursor already equals the acked watermark" do
    @node.update_columns(changelog_cursor: 5, changelog_acked: 5)
    stub_changelog([], since: 5)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 5, @node.reload.changelog_acked
    assert_not_requested :post, "#{@base}/v1/admin/changelog/ack"
  end

  test "a failed ack leaves changelog_acked unchanged while the cursor still advances" do
    stub_changelog([task_entry(1, "t1", status: "completed")])
    stub_request(:post, "#{@base}/v1/admin/changelog/ack").to_return(status: 500) # override the setup stub
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, @node.reload.changelog_cursor
    assert_equal 0, @node.changelog_acked
  end

  # --- idempotency (pilot behavior preserved) ------------------------------------

  test "re-projecting the same action is idempotent (insert-if-absent)" do
    stub_changelog([entry(1, "a1")])
    Agent::ChangelogProjector.new(@node).call
    @node.update_column(:changelog_cursor, 0) # simulate re-pull of same seq
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, ContainerActionRequest.where(action_id: "a1").count
  end

  test "re-emission after dispatch does not re-run the handler" do
    stub_changelog([entry(1, "a1")])
    Agent::ChangelogProjector.new(@node).call
    ContainerActionServices::Sweep.new.call
    ContainerActionWorkers::DispatchWorker.drain
    assert_equal "done", ContainerActionRequest.find_by(action_id: "a1").status
    assert_equal 1, FakeActionHandler.calls

    @node.update_column(:changelog_cursor, 0)
    Agent::ChangelogProjector.new(@node).call
    ContainerActionServices::Sweep.new.call
    ContainerActionWorkers::DispatchWorker.drain
    assert_equal 1, FakeActionHandler.calls
  end

  # --- node_maintenance ------------------------------------------------------------

  test "a node_maintenance entry projects at the ENTRY seq (its payload has none), newest wins" do
    @node.update_columns(maintenance_requested: false, maintenance_holds: {}, maintenance_seq: 0, agent_instance_id: nil)
    stub_changelog([maintenance_entry(3, local: {"since" => 1, "reason" => "first", "by" => "root"}),
      maintenance_entry(5, local: {"since" => 1, "reason" => "docker-upgrade", "by" => "root"})])

    Agent::ChangelogProjector.new(@node).call

    @node.reload
    assert_equal 5, @node.maintenance_seq
    assert_equal "docker-upgrade", @node.maintenance_local_hold["reason"]
    assert @node.maintenance
    assert_equal 5, @node.changelog_cursor
  end

  test "the poll advertises node_maintenance" do
    stub = stub_request(:get, "#{@base}/v1/admin/changelog").with(query: hash_including("since" => "0"),
      headers: {"X-CS-Changelog-Types" => "node_maintenance"})
      .to_return(status: 200, body: {entries: [], high_water: 0}.to_json)
    Agent::ChangelogProjector.new(@node).call
    assert_requested stub
  end

  test "the ack is sent only after the maintenance projection committed" do
    @node.update_columns(maintenance_holds: {}, maintenance_seq: 0)
    stub_changelog([maintenance_entry(7, local: {"since" => 1, "reason" => "x", "by" => "root"})])
    seq_at_ack = nil
    stub_request(:post, "#{@base}/v1/admin/changelog/ack").to_return do
      seq_at_ack = Node.where(id: @node.id).pick(:maintenance_seq)
      {status: 200, body: {acked: 7}.to_json}
    end
    Agent::ChangelogProjector.new(@node).call
    assert_equal 7, seq_at_ack
    assert_equal 7, @node.reload.changelog_acked
  end

  test "a malformed node_maintenance entry halts below it" do
    bad = {"seq" => 2, "entity_type" => "node_maintenance", "entity_id" => "node", "op" => "upsert", "payload" => nil}
    stub_changelog([task_entry(1, "t1", status: "completed"), bad])
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, @node.reload.changelog_cursor
  end

  test "unknown types still halt, and high_water is NOT adopted past a halt" do
    unknown = {"seq" => 2, "entity_type" => "mystery", "entity_id" => "x", "op" => "upsert", "payload" => {}}
    stub_changelog([task_entry(1, "t1", status: "completed"), unknown], high_water: 50)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 1, @node.reload.changelog_cursor
  end

  test "high_water advances the cursor past rows the agent scanned but didn't return" do
    stub_changelog([task_entry(1, "t1", status: "completed")], high_water: 9)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 9, @node.reload.changelog_cursor
    assert_requested :post, "#{@base}/v1/admin/changelog/ack", body: {seq: 9}.to_json
  end

  test "an empty page adopts high_water, and never regresses the cursor" do
    @node.update_columns(changelog_cursor: 5, changelog_acked: 5)
    stub_changelog([], since: 5, high_water: 12)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 12, @node.reload.changelog_cursor

    WebMock.reset!
    stub_ack
    stub_changelog([], since: 12, high_water: 3)
    Agent::ChangelogProjector.new(@node).call
    assert_equal 12, @node.reload.changelog_cursor
  end
end
