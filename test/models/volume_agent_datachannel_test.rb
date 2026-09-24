require "test_helper"
require "minitest/mock"

##
# PR3 DOWN rewire: Volume desired-state PUT, backup-family task dispatch, repo_info source,
# and node resolution now flow over the cs-agent data channel (Agent::Client) instead of
# Consul KV. These are model-level tests, so the HTTP client is replaced with a recording
# double rather than WebMock.
# The recording double is FakeAgentClient (lib/test/fake_agent_client.rb, auto-required by
# test_helper): create_task echoes the submitted id as the real 202 does, or returns a forced
# value (e.g. false) to exercise the refusal path.
class VolumeAgentDatachannelTest < ActiveSupport::TestCase
  setup do
    @volume = volumes(:mysql)
    @node = nodes(:testone)
    @fake = FakeAgentClient.new
  end

  def with_fake(fake = @fake)
    Agent::Client.stub(:for_node, fake) { yield }
  end

  # --- repo_info (now sourced from AgentRepository) ------------------------------

  test "repo_info reads the projected AgentRepository row in the legacy hash shape" do
    AgentRepository.create!(name: @volume.name, size_on_disk: 100, total_size: 250,
      archives: ["auto-2020-01-01T00:00:00-m-2020-01-01T00:00:00"])
    info = @volume.repo_info
    assert_equal 100, info["usage"]
    assert_equal 250, info["size"]
    assert_equal 1, info["archives"].size
  end

  test "repo_info is {} when there is no repository row" do
    assert_equal({}, @volume.repo_info)
    assert_equal 0.0, @volume.backup_usage
    assert_equal [], @volume.list_archives
  end

  # --- node resolution -----------------------------------------------------------

  test "active_node resolves the volume's online node" do
    assert_equal @node, @volume.active_node
  end

  # --- update_consul! → put_volume ----------------------------------------------

  test "update_consul! PUTs the desired-state to active_node with the real project_id, no last_backup" do
    with_fake { assert @volume.update_consul! }
    call = @fake.calls_of(:put_volume).first
    assert_not_nil call
    _, project_id, name, desired = call
    assert_equal @volume.deployment.id.to_s, project_id
    assert_equal @volume.name, name
    assert_equal @volume.deployment.id, desired[:project_id]
    refute desired.key?(:last_backup), "last_backup must not be sent DOWN (agent ignores it)"
  end

  test "update_consul! early-returns true (no PUT) when there is no online node" do
    @node.update_columns(disconnected: true)
    with_fake { assert_equal true, @volume.update_consul! }
    assert_empty @fake.calls
  end

  test "a detached volume uses the sentinel 0 in the URL path, task body, and config" do
    detached = nil
    with_fake do
      detached = Volume.create!(label: "detached", region: regions(:regionone), user: users(:admin))
      detached.nodes << @node
      @fake.calls.clear
      detached.update_consul!
    end
    assert_equal 0, detached.agent_project_id
    _, project_id, _name, desired = @fake.calls_of(:put_volume).first
    assert_equal "0", project_id
    assert_equal 0, desired[:project_id]
  end

  # --- backup-family dispatch ----------------------------------------------------

  test "create_backup! self-heals the volume then POSTs a UUID-id volume.backup task" do
    audit = Audit.create!(event: "backup.create", rel_id: @volume.id, rel_model: "Volume")
    @volume.current_audit = audit

    jid = with_fake { @volume.create_backup!("my snap") }

    # Self-heal PUT precedes the task dispatch.
    assert_equal 1, @fake.calls_of(:put_volume).size
    task = @fake.calls_of(:create_task).first[1]
    assert_equal jid, task[:id]
    assert_match(/\A[0-9a-f-]{36}\z/, jid, "id must be a UUID, never a volume.trash: form")
    assert_equal "volume.backup", task[:name]
    assert_equal @volume.name, task[:volume]
    assert_equal @node.hostname, task[:node]
    assert_equal @volume.deployment.id.to_s, task[:project_id]
    assert_equal @volume.name, task[:params][:source_volume]
    assert_equal "my-snap", task[:archive]
    # The audit is NOT used to carry the task id. It used to be, as a YAML *string* written
    # into the serialized raw_data column — which Audit#formatted_name returns verbatim, so
    # every backup rendered its audit line as "Me updated ---\n:task_id: ...". Nothing read it
    # back; correlation is the `task_id` label on the EventLog. Guard the regression.
    assert_nil audit.reload.raw_data
  end

  test "create_backup! honors a pre-minted task id" do
    jid = with_fake { @volume.create_backup!("my-snap", task_id: "11111111-2222-3333-4444-555555555555") }
    assert_equal "11111111-2222-3333-4444-555555555555", jid
    assert_equal jid, @fake.calls_of(:create_task).first[1][:id]
  end

  test "restore_backup! dispatches volume.restore with the source volume in params" do
    jid = with_fake { @volume.restore_backup!("snap-x", "other-vol") }
    task = @fake.calls_of(:create_task).first[1]
    assert_equal jid, task[:id]
    assert_equal "volume.restore", task[:name]
    assert_equal "other-vol", task[:params][:source_volume]
  end

  test "delete_backup! and export_backup! dispatch their task kinds" do
    with_fake { @volume.delete_backup!("snap-x") }
    with_fake { @volume.export_backup!("snap-x") }
    names = @fake.calls_of(:create_task).map { |c| c[1][:name] }
    assert_includes names, "backup.delete"
    assert_includes names, "backup.export"
  end

  test "restore_backup! refuses a blank snapshot name" do
    with_fake { refute @volume.restore_backup!("") }
    assert_empty @fake.calls_of(:create_task)
  end

  test "create_backup! returns false when the task dispatch is refused" do
    refusing = FakeAgentClient.new(create_task: false)
    result = with_fake(refusing) { @volume.create_backup!("snap") }
    assert_equal false, result
  end
end
