require "test_helper"
require "minitest/mock"
require "rake"

##
# The cutover backfill (rollout step 5) is the gate that unblocks backup/restore/export/delete
# dispatch: Agent::Client#create_task refuses any node whose datachannel_backfilled_at is nil.
# These tests pin the two properties an operator's safety depends on — a node only latches after
# a genuinely complete pass, and a node that never entered the pass is reported rather than
# silently omitted from the summary.
class AgentDatachannelBackfillTest < ActiveSupport::TestCase
  class FakeAgentClient
    attr_reader :firewall_calls, :volume_calls

    def initialize(firewall_result: true)
      @firewall_result = firewall_result
      @firewall_calls = []
      @volume_calls = []
    end

    def put_firewall_rules(host, rules)
      @firewall_calls << [host, rules]
      @firewall_result
    end

    def put_volume(project_id, name, data)
      @volume_calls << [project_id, name, data]
      true
    end
  end

  # Guard on the task being defined, not on a per-class flag: Rails.application.load_tasks
  # APPENDS the task body as another action every time it runs, so a second class loading
  # tasks in the same process would make this task's body execute twice.
  def self.load_tasks_once
    Rails.application.load_tasks unless Rake::Task.task_defined?("agent:datachannel_backfill")
  end

  setup do
    self.class.load_tasks_once
    @task = Rake::Task["agent:datachannel_backfill"]
    @task.reenable
    @node = nodes(:testone)
    Node.where.not(id: @node.id).update_all(datachannel_backfilled_at: nil)
    @node.update_column(:datachannel_backfilled_at, nil)
    @fake = FakeAgentClient.new
  end

  teardown do
    ENV.delete("NODE_ID")
    ENV.delete("NODE")
  end

  def run_task
    capture_io { Agent::Client.stub(:for_node, @fake) { @task.invoke } }.first
  end

  # The task now exits non-zero on any per-node/per-volume failure, so a failing pass
  # raises SystemExit out of Rake::Task#invoke. capture_io cannot be used: the exception
  # unwinds past it, so redirect $stdout by hand and keep what was written.
  def capture_exiting
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    error = assert_raises(SystemExit) { yield }
    [captured.string, error]
  ensure
    $stdout = original
  end

  def run_failing_task
    capture_exiting { Agent::Client.stub(:for_node, @fake) { @task.invoke } }
  end

  test "latches an online node after a fully successful pass" do
    out = run_task
    assert_not_nil @node.reload.datachannel_backfilled_at
    assert_match(/\[latched\] node #{@node.id}/, out)
    assert_match(/are backfilled/, out)
  end

  test "does not latch when the firewall PUT fails" do
    @fake = FakeAgentClient.new(firewall_result: false)
    out, error = run_failing_task
    assert_nil @node.reload.datachannel_backfilled_at
    assert_match(/\[fail\] firewall node #{@node.id}/, out)
    assert_match(/\[not-latched\] node #{@node.id}/, out)
    # Printing [fail] and exiting 0 let the provisioner record a successful seed while
    # backup/restore dispatch stayed blocked for that node.
    assert_equal 1, error.status
    assert_match(/agent:datachannel_backfill FAILED/, out)
  end

  ##
  # NODE_ID / NODE scoping. The provisioner uses this when attaching one node to a live
  # fleet: a full-fleet pass would re-PUT desired state to every existing node, and one
  # unrelated failure would mask the result for the node it actually asked about.

  test "NODE_ID limits the pass to that node and leaves the rest of the fleet alone" do
    other = duplicate_node(label: "other-node")
    ENV["NODE_ID"] = @node.id.to_s

    out = run_task

    assert_not_nil @node.reload.datachannel_backfilled_at
    assert_nil other.reload.datachannel_backfilled_at, "an unscoped node must not be touched"
    assert_match(/Scoped to node #{@node.id}/, out)
    assert_match(/\[latched\] node #{@node.id}/, out)
    refute_match(/node #{other.id}/, out)
    assert_equal 1, @fake.firewall_calls.size
  end

  test "NODE selects by hostname" do
    ENV["NODE"] = @node.hostname
    out = run_task
    assert_match(/Scoped to node #{@node.id}/, out)
    assert_not_nil @node.reload.datachannel_backfilled_at
  end

  test "an unknown NODE_ID exits non-zero rather than silently running the whole fleet" do
    ENV["NODE_ID"] = "0"
    out, error = capture_exiting { @task.invoke }
    assert_equal 1, error.status
    assert_match(/no node matching NODE_ID=0/, out)
    assert_nil @node.reload.datachannel_backfilled_at
  end

  test "a scoped run exits non-zero when its own node does not latch" do
    @fake = FakeAgentClient.new(firewall_result: false)
    ENV["NODE_ID"] = @node.id.to_s
    out, error = run_failing_task
    assert_equal 1, error.status
    assert_match(/scoped node #{@node.id} is not latched/, out)
  end

  ##
  # Node.online excludes disconnected AND maintenance nodes, so such a node never produces a
  # line in the pass and never enters the latch summary. Before the [pending] block a run could
  # end "latched 1/1" while a maintenance node stayed permanently gated out of dispatch.
  test "reports a maintenance node that the pass never touched" do
    other = duplicate_node(maintenance: true, label: "maint-node")
    out = run_task

    assert_nil other.reload.datachannel_backfilled_at
    assert_match(/WARNING: 1 node\(s\) NOT backfilled/, out)
    assert_match(/\[pending\] node #{other.id} \(maint-node\): in maintenance mode/, out)
    refute_match(/are backfilled/, out)
  end

  test "reports a disconnected node that the pass never touched" do
    other = duplicate_node(disconnected: true, label: "gone-node")
    out = run_task
    assert_match(/\[pending\] node #{other.id} \(gone-node\): disconnected/, out)
  end

  ##
  # A node first seen in the volume loop (it came online mid-run) has had no firewall push, so
  # latching it would make "backfilled" a lie until the next ingress change.
  test "does not latch a node that only appears in the volume loop" do
    volume = volumes(:mysql)
    late = duplicate_node(label: "late-node")
    # The node is genuinely online (so the volume loop resolves it) but was not in the
    # firewall pass's Node.online snapshot — i.e. it came online between the two loops.
    Node.stub(:online, Node.where(id: @node.id)) do
      volume.stub(:nodes, Node.where(id: late.id)) do
        volume.stub(:active_node, late) do
          Volume.stub(:find_each, ->(&blk) { blk.call(volume) }) do
            out = capture_io { Agent::Client.stub(:for_node, @fake) { @task.invoke } }.first
            assert_nil late.reload.datachannel_backfilled_at
            assert_match(/came online mid-pass, no firewall push/, out)
            assert_match(/\[pending\] node #{late.id}/, out)
          end
        end
      end
    end
  end

  private

  def duplicate_node(label:, maintenance: false, disconnected: false)
    attrs = @node.attributes.except("id", "created_at", "updated_at")
    Node.create!(
      attrs.merge(
        "label" => label,
        "hostname" => "#{label}.example.com",
        "maintenance" => maintenance,
        "disconnected" => disconnected,
        "datachannel_backfilled_at" => nil
      )
    )
  end
end
